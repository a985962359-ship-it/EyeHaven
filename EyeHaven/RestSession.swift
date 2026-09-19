import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications
import notify

/// Lock / screen-off, including devices without a passcode.
@MainActor
final class DeviceLockMonitor {
    static let shared = DeviceLockMonitor()

    private(set) var isLocked = false
    var onChange: (() -> Void)?

    private var started = false
    private var tokens: [Int32] = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard !started else { return }
        started = true
        refresh()
        observeState("com.apple.springboard.lockstate")
        observeState("com.apple.springboard.hasBlankedScreen")
        observeState("com.apple.iokit.hid.displayStatus")
        observePulse("com.apple.springboard.lockcomplete")
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyLocked(true) }
        })
        observers.append(center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    func refresh() {
        applyLocked(Self.probeLocked())
    }

    /// Screen is on and the device is not locked — the user is in another app.
    func isUsingAnotherApp() -> Bool {
        guard UIApplication.shared.applicationState == .background else { return false }
        if isLocked || Self.probeLocked() { return false }
        // Only treat as leaving rest when the display reports ON.
        // If we cannot read it, do not guess — lock/unlock must not fail a check-in.
        guard let display = Self.notifyState("com.apple.iokit.hid.displayStatus") else { return false }
        return display != 0
    }

    private func applyLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        onChange?()
    }

    private func observeState(_ name: String) {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if status == NOTIFY_STATUS_OK {
            tokens.append(token)
        }
    }

    private func observePulse(_ name: String) {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
            Task { @MainActor in self?.applyLocked(true) }
        }
        if status == NOTIFY_STATUS_OK {
            tokens.append(token)
        }
    }

    private static func probeLocked() -> Bool {
        if !UIApplication.shared.isProtectedDataAvailable { return true }
        if let state = notifyState("com.apple.springboard.lockstate"), state != 0 { return true }
        if let state = notifyState("com.apple.springboard.hasBlankedScreen"), state != 0 { return true }
        if let state = notifyState("com.apple.iokit.hid.displayStatus"), state == 0 { return true }
        return false
    }

    private static func notifyState(_ name: String) -> UInt64? {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return nil }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return nil }
        return state
    }
}

enum SessionPhase: String, Codable, Equatable {
    case idle
    case working
    case paused
    case restDue
    case resting
    case restExtra
}

enum ExtraRestReward {
    static let extraMinutes = 5
    static let nextUseMinutes = 2
}

@MainActor
@Observable
final class RestSession {
    static let checkInGrace: TimeInterval = 120

    var workMinutes: Int = 20
    var restMinutes: Int = 10
    var dailyLimitMinutes: Int = 60
    var skippedRestAlertCount: Int = 3
    var rewardExtraRest: Bool = true

    private(set) var phase: SessionPhase = .idle
    private(set) var remaining: TimeInterval = 20 * 60
    private(set) var blockUsed: TimeInterval = 0
    private(set) var checkInDeadline: Date?
    private(set) var displayNow = Date()

    private var workEndsAt: Date?
    private var restEndsAt: Date?
    private var restDueAt: Date?
    private var report: DailyReport?
    private var didRestore = false
    private var tickTimer: Timer?
    private var leaveRestTask: Task<Void, Never>?
    private var deviceLocked = false
    private var didObserveLock = false
    private var backgroundedAt: Date?
    private var resumedFromPauseInBackground = false
    private var stayedPausedForLock = false
    private var stayedRestingForLock = false
    private var leftRestForOtherApp = false

    var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    var restDuration: TimeInterval { TimeInterval(restMinutes * 60) }

    /// Stable end of the required rest. Used by the UIKit countdown label.
    var restAnchorDate: Date? { restEndsAt }

    func remaining(at date: Date = .now) -> TimeInterval {
        switch phase {
        case .working:
            return max(0, workEndsAt?.timeIntervalSince(date) ?? remaining)
        case .restDue:
            return max(0, checkInDeadline?.timeIntervalSince(date) ?? remaining)
        case .resting:
            return max(0, restEndsAt?.timeIntervalSince(date) ?? remaining)
        case .restExtra:
            return max(0, date.timeIntervalSince(restEndsAt ?? date))
        case .paused, .idle:
            return remaining
        }
    }

    var showsRestPage: Bool {
        phase == .restDue || phase == .resting || phase == .restExtra
    }

    var progress: Double {
        switch phase {
        case .resting:
            guard restDuration > 0 else { return 0 }
            return 1 - (remaining / restDuration)
        case .restDue:
            guard let deadline = checkInDeadline else { return 0 }
            let window = Self.checkInGrace
            let left = max(0, deadline.timeIntervalSinceNow)
            return 1 - (left / window)
        case .working, .paused:
            let total = min(workDuration, TimeInterval(remainingDailySeconds) + blockUsed)
            guard total > 0 else { return 0 }
            return blockUsed / total
        case .idle:
            return 0
        case .restExtra:
            return 1
        }
    }

    var remainingDailySeconds: Int {
        report?.remainingSeconds(dailyLimitMinutes: dailyLimitMinutes) ?? dailyLimitMinutes * 60
    }

    /// Next work block if the child taps 开始使用 now.
    var nextUseDuration: TimeInterval {
        let bonus = rewardExtraRest ? (report?.nextBonusMinutes ?? 0) : 0
        let minutes = workMinutes + bonus
        return min(TimeInterval(minutes * 60), TimeInterval(max(0, remainingDailySeconds)))
    }

    var headline: String {
        switch phase {
        case .idle:
            remainingDailySeconds <= 0 ? "今天的使用时间到了" : "准备开始"
        case .working: "使用中"
        case .paused: "已暂停"
        case .restDue: "请打开休息页打卡"
        case .resting: "休息打卡中"
        case .restExtra: "可以继续休息"
        }
    }

    var subtitle: String {
        switch phase {
        case .idle:
            remainingDailySeconds <= 0
                ? "额度已用完。报告已写给家长。"
                : idleSubtitle
        case .working:
            rewardExtraRest
                ? "请留在记时页。划掉 App 记为未打卡。切到其他 App 会继续计时。多休息 \(ExtraRestReward.extraMinutes) 分钟，下次使用时间增加 \(ExtraRestReward.nextUseMinutes) 分钟。"
                : "请留在记时页。划掉 App 记为未打卡。切到其他 App 会继续计时。"
        case .paused:
            "可以暂停去上厕所或休息。请留在这一页或锁屏。切到其他 App 会马上继续计时，划掉 App 记为未打卡。"
        case .restDue:
            "超过 2 分钟没打开休息页，或把 App 划掉，会记为未休息。"
        case .resting:
            "请留在这一页。切到其他 App 或划掉都会记为未休息。锁屏熄屏可以。"
        case .restExtra:
            extraRestSubtitle
        }
    }

    private var idleSubtitle: String {
        let bonus = rewardExtraRest ? (report?.nextBonusMinutes ?? 0) : 0
        let bonusText = bonus > 0 ? "下次使用将多 \(bonus) 分钟。" : ""
        return "用 \(workMinutes) 分钟，休息 \(restMinutes) 分钟。今天还可使用 \(max(0, remainingDailySeconds / 60)) 分钟。\(bonusText)"
    }

    private var extraRestSubtitle: String {
        if rewardExtraRest {
            return "最少休息已完成。留在这一页再多休息 \(ExtraRestReward.extraMinutes) 分钟，下次使用时间增加 \(ExtraRestReward.nextUseMinutes) 分钟。切到其他 App 会开始下一段使用计时。"
        }
        return "最少休息已完成。可以继续歇着。切到其他 App 会开始下一段使用计时。"
    }

    func attach(report: DailyReport) {
        self.report = report
        if !didRestore {
            restore()
            didRestore = true
            handleColdLaunch()
        } else {
            catchUp()
        }
        if phase == .working {
            scheduleWorkEndAlerts()
        }
        ParentNotifier.cancelRestFinished()
        observeLockState()
        startTicking()
    }

    func apply(_ settings: ParentSettings) {
        workMinutes = settings.workMinutes
        restMinutes = settings.restMinutes
        dailyLimitMinutes = settings.dailyLimitMinutes
        skippedRestAlertCount = settings.skippedRestAlertCount
        rewardExtraRest = settings.rewardExtraRest
        if phase == .idle {
            remaining = workDuration
            blockUsed = 0
        }
    }

    func start(at date: Date = Date()) {
        guard remainingDailySeconds > 0 else { return }
        phase = .working
        blockUsed = 0
        let bonus = rewardExtraRest ? (report?.consumeBonus() ?? 0) : 0
        let minutes = workMinutes + bonus
        let length = min(TimeInterval(minutes * 60), TimeInterval(max(0, remainingDailySeconds)))
        remaining = length
        workEndsAt = date.addingTimeInterval(length)
        restDueAt = nil
        restEndsAt = nil
        checkInDeadline = nil
        stayedRestingForLock = false
        persist()
        scheduleWorkEndAlerts()
        startTicking()
        catchUp()
    }

    func pause() {
        guard phase == .working else { return }
        catchUp()
        phase = .paused
        workEndsAt = nil
        persist()
        ParentNotifier.cancelRestNotifications()
    }

    func resume(at date: Date = Date()) {
        guard phase == .paused else { return }
        if remainingDailySeconds <= 0 {
            enterRestDue(at: date)
            return
        }
        remaining = min(remaining, TimeInterval(remainingDailySeconds))
        workEndsAt = date.addingTimeInterval(remaining)
        phase = .working
        persist()
        scheduleWorkEndAlerts()
        startTicking()
        catchUp()
        if UIApplication.shared.applicationState == .active {
            resumedFromPauseInBackground = false
        }
    }

    func stopAndRest() {
        guard phase == .working || phase == .paused else { return }
        if phase == .working {
            catchUp()
        }
        guard phase == .working || phase == .paused else { return }
        clearRestNotifications()
        workEndsAt = nil
        enterRestDue(at: Date())
    }

    /// Stay on the rest page: check in if rest is due.
    func restPageDidAppear() {
        catchUp()
        if phase == .restDue {
            checkIn()
        }
    }

    /// SwiftUI also disappears when the screen locks. Leaving rest is decided after we know it is another app.
    func restPageDidDisappear() {}

    func handleScenePhase(_ scenePhase: ScenePhase) {
        DeviceLockMonitor.shared.refresh()
        switch scenePhase {
        case .active:
            cancelLeaveRestFail()
            if leftRestForOtherApp, phase == .restDue || phase == .resting {
                leftRestForOtherApp = false
                failRest(reason: "离开了休息页")
                startTicking()
                return
            }
            leftRestForOtherApp = false
            settleAfterReturningToForeground()
            startTicking()
        case .inactive:
            cancelLeaveRestFail()
            markRestingIfLocked()
            if phase == .paused || phase == .restDue || phase == .resting || phase == .restExtra {
                backgroundedAt = Date()
            }
            persist()
        case .background:
            backgroundedAt = Date()
            markRestingIfLocked()
            persist()
            UserDefaults.standard.synchronize()
            handleBackgrounded()
        @unknown default:
            break
        }
    }

    private func observeLockState() {
        DeviceLockMonitor.shared.start()
        DeviceLockMonitor.shared.refresh()
        guard !didObserveLock else { return }
        didObserveLock = true
        DeviceLockMonitor.shared.onChange = { [weak self] in
            self?.lockStateChanged()
        }
    }

    private func lockStateChanged() {
        if DeviceLockMonitor.shared.isLocked {
            cancelLeaveRestFail()
            markRestingIfLocked()
            keepPauseIfLocked()
        }
    }

    private func markRestingIfLocked() {
        guard DeviceLockMonitor.shared.isLocked else { return }
        deviceLocked = true
        if phase == .restDue || phase == .resting || phase == .restExtra {
            stayedRestingForLock = true
            leftRestForOtherApp = false
            persist()
        }
    }

    private func cancelLeaveRestFail() {
        leaveRestTask?.cancel()
        leaveRestTask = nil
    }

    private func isScreenLocked() -> Bool {
        DeviceLockMonitor.shared.isLocked || !UIApplication.shared.isProtectedDataAvailable
    }

    private func keepPauseIfLocked() {
        guard isScreenLocked(), phase == .working, resumedFromPauseInBackground else { return }
        pause()
        resumedFromPauseInBackground = false
        stayedPausedForLock = true
    }

    private func settleAfterReturningToForeground() {
        if stayedPausedForLock {
            stayedPausedForLock = false
            backgroundedAt = nil
            return
        }
        // Lock then unlock always comes back active and unlocked. That is not leaving rest.
        if stayedRestingForLock || phase == .restDue || phase == .resting || phase == .restExtra {
            stayedRestingForLock = false
            backgroundedAt = nil
            catchUp()
            return
        }
        let left = backgroundedAt
        let away = left.map { Date().timeIntervalSince($0) } ?? 0
        defer { backgroundedAt = nil }
        guard away >= 0.6, !isScreenLocked() else { return }
        if phase == .paused {
            resume(at: left ?? Date())
        }
    }

    private func handleBackgrounded() {
        DeviceLockMonitor.shared.refresh()
        if isScreenLocked() {
            if phase == .paused {
                stayedPausedForLock = true
            }
            markRestingIfLocked()
            return
        }
        switch phase {
        case .paused:
            resumeAfterLeavingPause()
        case .restDue, .resting:
            scheduleLeaveRestFailIfNeeded()
        case .restExtra:
            scheduleExtraRestSwitchAway()
        default:
            break
        }
    }

    private func resumeAfterLeavingPause() {
        guard phase == .paused, !isScreenLocked() else { return }
        resumedFromPauseInBackground = true
        resume(at: backgroundedAt ?? Date())
        UserDefaults.standard.synchronize()
    }

    /// Pause is only for staying on this screen or locking. Switching apps resumes the work timer.
    private func schedulePausedSwitchAway() {
        resumeAfterLeavingPause()
    }

    private func scheduleLeaveRestFailIfNeeded() {
        guard phase == .restDue || phase == .resting else { return }
        cancelLeaveRestFail()
        leaveRestTask = Task { @MainActor in
            let started = Date()
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                DeviceLockMonitor.shared.refresh()
                markRestingIfLocked()
                if stayedRestingForLock || isScreenLocked() { return }
            }
            guard !Task.isCancelled else { return }
            guard phase == .restDue || phase == .resting else { return }
            // Sleep across a lock-suspend takes much longer than 1.2s of wall time.
            if Date().timeIntervalSince(started) > 2.0 {
                stayedRestingForLock = true
                persist()
                return
            }
            guard UIApplication.shared.applicationState == .background else { return }
            guard DeviceLockMonitor.shared.isUsingAnotherApp() else { return }
            leftRestForOtherApp = true
            failRest(reason: "离开了休息页")
        }
    }

    private func scheduleExtraRestSwitchAway() {
        guard phase == .restExtra else { return }
        cancelLeaveRestFail()
        leaveRestTask = Task { @MainActor in
            let started = Date()
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                DeviceLockMonitor.shared.refresh()
                markRestingIfLocked()
                if stayedRestingForLock || isScreenLocked() { return }
            }
            guard !Task.isCancelled else { return }
            guard phase == .restExtra else { return }
            if Date().timeIntervalSince(started) > 2.0 {
                stayedRestingForLock = true
                persist()
                return
            }
            guard UIApplication.shared.applicationState == .background else { return }
            guard DeviceLockMonitor.shared.isUsingAnotherApp() else { return }
            continueUseAfterLeavingExtraRest()
        }
    }

    private func continueUseAfterLeavingExtraRest() {
        guard phase == .restExtra else { return }
        let startedAt = backgroundedAt ?? Date()
        endExtraRest(grantBonus: false)
        guard remainingDailySeconds > 0 else { return }
        start(at: startedAt)
    }

    /// Killing the process is different from locking the screen: lock keeps the app in memory.
    private func handleColdLaunch() {
        if stayedRestingForLock, phase == .restDue || phase == .resting || phase == .restExtra {
            catchUp()
            return
        }
        switch phase {
        case .paused:
            failRest(reason: "暂停时关掉了应用")
        case .working:
            accountWorkingUsage()
            failRest(reason: "使用时关掉了应用")
        case .resting:
            failRest(reason: "休息时关掉了应用")
        case .restExtra:
            continueUseAfterLeavingExtraRest()
        default:
            catchUp()
        }
    }

    func catchUp() {
        displayNow = Date()
        guard phase != .idle, phase != .paused else { return }
        let now = displayNow
        if phase == .working, let end = workEndsAt {
            accountWorkingUsage(now: now, end: end)
            if remaining <= 0 || remainingDailySeconds <= 0 {
                let dueAt = remaining <= 0 ? end : now
                enterRestDue(at: dueAt)
                settleRestDue(at: now)
            }
        } else if phase == .restDue {
            settleRestDue(at: now)
        } else if phase == .resting, let end = restEndsAt {
            remaining = max(0, end.timeIntervalSince(now))
            if remaining <= 0 {
                enterRestExtra()
            }
        } else if phase == .restExtra {
            remaining = max(0, now.timeIntervalSince(restEndsAt ?? now))
        }
    }

    private func settleRestDue(at now: Date) {
        guard phase == .restDue, let deadline = checkInDeadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if now >= deadline {
            failRest(reason: "超时未打开休息页")
        }
    }

    private func enterRestDue(at dueAt: Date) {
        phase = .restDue
        remaining = Self.checkInGrace
        restDueAt = dueAt
        checkInDeadline = dueAt.addingTimeInterval(Self.checkInGrace)
        workEndsAt = nil
        restEndsAt = nil
        persist()
        if UIApplication.shared.applicationState == .active {
            ParentNotifier.restDueHaptic()
        }
        maybeNotifyQuota()
    }

    private func scheduleWorkEndAlerts() {
        guard let end = workEndsAt else { return }
        ParentNotifier.scheduleRestDue(at: end, graceSeconds: Self.checkInGrace)
        ParentNotifier.scheduleMissedCheckIn(at: end.addingTimeInterval(Self.checkInGrace))
    }

    private func checkIn() {
        guard phase == .restDue else { return }
        clearRestNotifications()
        phase = .resting
        restEndsAt = Date().addingTimeInterval(restDuration)
        remaining = restDuration
        persist()
    }

    private func accountWorkingUsage(now: Date = Date(), end: Date? = nil) {
        guard phase == .working, let end = end ?? workEndsAt else { return }
        let remainingWork = max(0, end.timeIntervalSince(now))
        let elapsed = remaining - remainingWork
        if elapsed > 0 {
            report?.addUsage(seconds: elapsed)
            blockUsed += elapsed
            maybeNotifyQuota()
        }
        remaining = remainingWork
    }

    private func failRest(reason: String) {
        guard phase == .restDue || phase == .resting || phase == .paused || phase == .working else { return }
        clearRestNotifications()
        let shouldAlert = report?.skipRest(alertAfter: skippedRestAlertCount, reason: reason) ?? false
        let count = report?.today.skippedRests ?? 1
        ParentNotifier.checkInFailed(reason: reason, count: count)
        if shouldAlert {
            ParentNotifier.skippedRestAlert(
                count: count,
                threshold: skippedRestAlertCount
            )
        }
        returnToIdle()
    }

    func finishRestAndStartUsing() {
        endExtraRest(grantBonus: true)
        guard remainingDailySeconds > 0 else { return }
        start()
    }

    func endExtraRest(grantBonus: Bool = true) {
        guard phase == .restExtra else { return }
        let extra = Date().timeIntervalSince(restEndsAt ?? Date())
        let extraMinutes = max(0, Int(extra / 60))
        let bonus = grantBonus && rewardExtraRest && extraMinutes >= ExtraRestReward.extraMinutes
            ? ExtraRestReward.nextUseMinutes
            : 0
        report?.recordCheckIn(succeeded: true, extraMinutes: extraMinutes, bonusMinutes: bonus)
        returnToIdle()
    }

    private func enterRestExtra() {
        report?.completeRest()
        phase = .restExtra
        remaining = 0
        persist()
    }

    private func returnToIdle() {
        phase = .idle
        remaining = workDuration
        blockUsed = 0
        workEndsAt = nil
        restDueAt = nil
        restEndsAt = nil
        checkInDeadline = nil
        stayedRestingForLock = false
        leftRestForOtherApp = false
        persist()
        maybeNotifyQuota()
    }

    private func maybeNotifyQuota() {
        guard remainingDailySeconds <= 0 else { return }
        guard report?.markQuotaExhausted() == true else { return }
        ParentNotifier.quotaExhausted(
            summary: report?.summaryText(
                dailyLimitMinutes: dailyLimitMinutes,
                alertAfter: skippedRestAlertCount
            ) ?? "今天的使用额度已用完。"
        )
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.catchUp()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        catchUp()
    }

    private func clearRestNotifications() {
        ParentNotifier.cancelRestNotifications()
    }

    private enum PersistKey {
        static let snapshot = "session.snapshot"
    }

    private struct Snapshot: Codable {
        var phase: SessionPhase
        var remaining: TimeInterval
        var blockUsed: TimeInterval
        var workEndsAt: Date?
        var restDueAt: Date?
        var restEndsAt: Date?
        var checkInDeadline: Date?
        var backgroundedAt: Date?
        var stayedRestingForLock: Bool?
    }

    private func persist() {
        let snapshot = Snapshot(
            phase: phase,
            remaining: remaining,
            blockUsed: blockUsed,
            workEndsAt: workEndsAt,
            restDueAt: restDueAt,
            restEndsAt: restEndsAt,
            checkInDeadline: checkInDeadline,
            backgroundedAt: backgroundedAt,
            stayedRestingForLock: stayedRestingForLock
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistKey.snapshot)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: PersistKey.snapshot),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        phase = snapshot.phase
        remaining = snapshot.remaining
        blockUsed = snapshot.blockUsed
        workEndsAt = snapshot.workEndsAt
        restDueAt = snapshot.restDueAt
        restEndsAt = snapshot.restEndsAt
        checkInDeadline = snapshot.checkInDeadline
        backgroundedAt = snapshot.backgroundedAt
        stayedRestingForLock = snapshot.stayedRestingForLock ?? false
    }
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
