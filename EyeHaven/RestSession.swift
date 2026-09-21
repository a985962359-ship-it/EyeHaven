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
    /// Display is off / device is locked. Does not use protected-data alone, which can flicker when switching apps.
    private(set) var isScreenOff = false
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
            Task { @MainActor in
                self?.isScreenOff = true
                self?.applyLocked(true)
            }
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
        isScreenOff = Self.probeScreenOff()
        applyLocked(Self.probeLocked() || isScreenOff)
    }

    /// Side-button lock only. Protected data flickers when switching apps and must not count.
    func isKeyLocked() -> Bool {
        if let state = Self.notifyState("com.apple.springboard.lockstate"), state != 0 { return true }
        return false
    }

    /// Screen is on and the device is not locked — the user is in another app.
    func isUsingAnotherApp() -> Bool {
        guard UIApplication.shared.applicationState == .background else { return false }
        if isKeyLocked() { return false }
        if isScreenOff || Self.probeScreenOff() { return false }
        guard let display = Self.notifyState("com.apple.iokit.hid.displayStatus") else {
            return !isKeyLocked()
        }
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
            Task { @MainActor in
                self?.isScreenOff = true
                self?.applyLocked(true)
            }
        }
        if status == NOTIFY_STATUS_OK {
            tokens.append(token)
        }
    }

    private static func probeLocked() -> Bool {
        if !UIApplication.shared.isProtectedDataAvailable { return true }
        return probeScreenOff()
    }

    private static func probeScreenOff() -> Bool {
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
    /// Extra rest needed after the required rest before any next-use bonus.
    static let extraMinutes = 10
    /// Next-use bonus is capped here each time.
    static let nextUseMinutes = 5
    static let recordedExtraCap = 99

    static func bonusMinutes(extra: Int) -> Int {
        guard extra >= extraMinutes else { return 0 }
        return min(nextUseMinutes, extra / 2)
    }

    static func displayExtraMinutes(_ extra: Int) -> Int {
        min(recordedExtraCap, max(0, extra))
    }
}

/// Session rules — keep these when changing this file:
/// 1. Rest starts only when the rest page is in front and the app is active.
/// 2. Lock never starts rest. It only keeps an already-started rest or pause.
/// 3. restDue + home / other app is expected. Do not fail.
/// 4. Leave-fail only while `.resting`, after 10 seconds away. Notify immediately. Extra-rest leave starts the next use.
/// 5. More than 2 minutes late: record 未按时, still rest, no celebration.
/// 6. Kill: working continues on wall-clock; pause without lock fails; resting fails.
/// 7. Pause: background resumes immediately; real lockstate re-pauses. Rest: background warns and freezes.
/// 8. 故事页 / TipsView / BedtimeStory 只展示文字。禁止接到本文件、通知、朗读或锁屏。
@MainActor
@Observable
final class RestSession {
    static let checkInGrace: TimeInterval = 120
    static let restLeaveGrace: TimeInterval = 10

    var workMinutes: Int
    var restMinutes: Int
    var dailyLimitMinutes: Int
    var skippedRestAlertCount: Int
    var rewardExtraRest: Bool

    init() {
        let settings = ParentSettings()
        workMinutes = settings.workMinutes
        restMinutes = settings.restMinutes
        dailyLimitMinutes = settings.dailyLimitMinutes
        skippedRestAlertCount = settings.skippedRestAlertCount
        rewardExtraRest = settings.rewardExtraRest
        remaining = TimeInterval(settings.workMinutes * 60)
    }

    private(set) var phase: SessionPhase = .idle
    private(set) var remaining: TimeInterval
    private(set) var blockUsed: TimeInterval = 0
    private(set) var checkInDeadline: Date?
    private(set) var displayNow = Date()

    private var workEndsAt: Date?
    private var restEndsAt: Date?
    private var restDueAt: Date?
    private var workLength: TimeInterval = 0
    private var pendingUsage: TimeInterval = 0
    private var lastUsageFlush = Date.distantPast
    private var report: DailyReport?
    private var didRestore = false
    private var tickTimer: Timer?
    private var leaveRestTask: Task<Void, Never>?
    private var deviceLocked = false
    private var didObserveLock = false
    private var backgroundedAt: Date?
    private var resumedFromPauseInBackground = false
    private var pauseWentToBackground = false
    private var stayedPausedForLock = false
    private var stayedRestingForLock = false
    private var leftRestForOtherApp = false
    private var missedCheckInRecorded = false
    private var restStartedOnPage = false
    private var restLeaveFrozenRemaining: TimeInterval?
    private var restLeftAt: Date?

    var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    var restDuration: TimeInterval { TimeInterval(restMinutes * 60) }

    /// Wall-clock end of the required rest. Display freeze uses `restLeaveDisplayFrozen`.
    var restAnchorDate: Date? { restEndsAt }

    /// Remaining rest to show while the child has 10 seconds to return. Stops the on-screen countdown.
    var restLeaveDisplayFrozen: TimeInterval? { restLeaveFrozenRemaining }

    func remaining(at date: Date = .now) -> TimeInterval {
        switch phase {
        case .working:
            return max(0, workEndsAt?.timeIntervalSince(date) ?? remaining)
        case .restDue:
            return max(0, checkInDeadline?.timeIntervalSince(date) ?? remaining)
        case .resting:
            if let frozen = restLeaveFrozenRemaining { return frozen }
            return max(0, restEndsAt?.timeIntervalSince(date) ?? remaining)
        case .restExtra:
            let extra = max(0, date.timeIntervalSince(restEndsAt ?? date))
            return min(TimeInterval(ExtraRestReward.recordedExtraCap * 60), extra)
        case .paused, .idle:
            return remaining
        }
    }

    var showsRestPage: Bool {
        phase == .restDue || phase == .resting || phase == .restExtra
    }

    /// They opened rest after the 2-minute window. Still must rest, but do not celebrate.
    var checkInWasLate: Bool { missedCheckInRecorded }

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
            let left = phase == .paused
                ? remaining
                : max(0, workEndsAt?.timeIntervalSinceNow ?? remaining)
            let total = blockUsed + left
            guard total > 0 else { return 0 }
            return min(1, blockUsed / total)
        case .idle:
            return 0
        case .restExtra:
            return 1
        }
    }

    var remainingDailySeconds: Int {
        let base = report?.remainingSeconds(dailyLimitMinutes: dailyLimitMinutes) ?? dailyLimitMinutes * 60
        return max(0, base - Int(pendingUsage.rounded()))
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
                ? "计时已开始。可以切到其他 App，时间会继续走。休息后再多歇 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多加 \(ExtraRestReward.nextUseMinutes) 分钟。"
                : "计时已开始。可以切到其他 App，时间会继续走。"
        case .paused:
            "暂停中。请留在这一页或锁屏。切到其他 App 会马上继续计时，划掉 App 记为未打卡。"
        case .restDue:
            "请打开休息页打卡。不打开会每 2 分钟提醒。超过 2 分钟记为未休息。锁屏不会开始休息。"
        case .resting:
            "休息已开始。请留在这一页或锁屏。切走会马上提醒你回来，10 秒内回来不算失败，超过 10 秒再回来会记失败。"
        case .restExtra:
            extraRestSubtitle
        }
    }

    private var idleSubtitle: String {
        let left = max(0, remainingDailySeconds)
        let dailyText: String
        if left == 0 {
            dailyText = "今天还可使用 0 分钟。"
        } else if left < 60 {
            dailyText = "今天还可使用不到 1 分钟。"
        } else {
            dailyText = "今天还可使用 \(left / 60) 分钟。"
        }
        let bonus = rewardExtraRest ? (report?.nextBonusMinutes ?? 0) : 0
        let bonusText = bonus > 0 ? "下次使用将多 \(bonus) 分钟。" : ""
        return "用 \(workMinutes) 分钟，休息 \(restMinutes) 分钟。\(dailyText)\(bonusText)"
    }

    private var extraRestSubtitle: String {
        if rewardExtraRest {
            return "最少休息已完成。留在这一页再多休息 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多增加 \(ExtraRestReward.nextUseMinutes) 分钟。切到其他 App 会开始下一段使用计时。"
        }
        return "最少休息已完成。可以继续歇着。切到其他 App 会开始下一段使用计时。"
    }

    func attach(report: DailyReport, settings: ParentSettings? = nil) {
        if let settings {
            apply(settings)
        }
        self.report = report
        if !didRestore {
            restore()
            didRestore = true
            handleColdLaunch()
        } else {
            catchUp()
        }
        flushUsage(force: true)
        if let settings {
            apply(settings)
        }
        if phase == .working {
            scheduleWorkEndAlerts()
        }
        ParentNotifier.cancelRestFinished()
        observeLockState()
        startTicking()
        beginRestIfPageIsInFront()
        if phase == .restDue, let due = restDueAt {
            ParentNotifier.scheduleRestNags(from: due)
        }
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
        guard phase == .idle else { return }
        guard remainingDailySeconds > 0 else { return }
        phase = .working
        blockUsed = 0
        let bonus = rewardExtraRest ? (report?.consumeBonus() ?? 0) : 0
        let minutes = workMinutes + bonus
        let length = min(TimeInterval(minutes * 60), TimeInterval(max(0, remainingDailySeconds)))
        remaining = length
        workLength = length
        pendingUsage = 0
        lastUsageFlush = date
        workEndsAt = date.addingTimeInterval(length)
        restDueAt = nil
        restEndsAt = nil
        checkInDeadline = nil
        stayedRestingForLock = false
        stayedPausedForLock = false
        missedCheckInRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        RestStoryPlayer.shared.stop()
        persist()
        scheduleWorkEndAlerts()
        startTicking()
        catchUp()
    }

    func pause() {
        guard phase == .working else { return }
        catchUp()
        // Time may have just run out; catchUp already moved to rest.
        guard phase == .working else { return }
        flushUsage(force: true)
        workLength = blockUsed + remaining
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
        workLength = blockUsed + remaining
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
            flushUsage(force: true)
        }
        guard phase == .working || phase == .paused else { return }
        clearRestNotifications()
        workEndsAt = nil
        enterRestDue(at: Date())
    }

    /// Rest starts only when this page is actually in front. Work ending after 去桌面 must not start rest.
    func restPageDidAppear() {
        if failLateReturnFromRestIfNeeded() { return }
        restoreRestAfterLeaveGrace()
        catchUp()
        beginRestIfPageIsInFront()
    }

    /// SwiftUI also disappears when the screen locks. Leaving rest is decided after we know it is another app.
    func restPageDidDisappear() {}

    func handleScenePhase(_ scenePhase: ScenePhase) {
        DeviceLockMonitor.shared.refresh()
        switch scenePhase {
        case .active:
            if failLateReturnFromRestIfNeeded() {
                startTicking()
                return
            }
            restoreRestAfterLeaveGrace()
            cancelLeaveRestFail()
            leftRestForOtherApp = false
            settleAfterReturningToForeground()
            startTicking()
            beginRestIfPageIsInFront()
            restartRestIfItBeganInBackground()
        case .inactive:
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                cancelLeaveRestFail()
                markRestingIfLocked()
            }
            if phase == .paused || phase == .restDue || phase == .resting || phase == .restExtra {
                backgroundedAt = Date()
            }
            persist()
        case .background:
            backgroundedAt = Date()
            if phase == .working {
                catchUp()
            }
            flushUsage(force: true)
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                cancelLeaveRestFail()
                markRestingIfLocked()
            }
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
        DeviceLockMonitor.shared.refresh()
        if DeviceLockMonitor.shared.isKeyLocked() {
            adoptRestLeaveIntoOngoingRest()
            cancelLeaveRestFail()
            keepRestIfLocked()
            if phase == .paused {
                stayedPausedForLock = true
                persist()
            }
            keepPauseIfLocked()
            return
        }
    }

    private func markRestingIfLocked() {
        keepRestIfLocked()
    }

    /// Lock never starts rest. It only keeps an already-started rest from being treated as leaving.
    private func keepRestIfLocked() {
        guard DeviceLockMonitor.shared.isKeyLocked() else { return }
        deviceLocked = true
        leftRestForOtherApp = false
        if phase == .restDue || phase == .resting || phase == .restExtra {
            stayedRestingForLock = true
        }
        persist()
    }

    private func cancelLeaveRestFail() {
        leaveRestTask?.cancel()
        leaveRestTask = nil
        ParentNotifier.cancelReturnToRest()
    }

    private func keepPauseIfLocked() {
        guard DeviceLockMonitor.shared.isKeyLocked() else { return }
        guard phase == .working, resumedFromPauseInBackground else { return }
        pause()
        resumedFromPauseInBackground = false
        stayedPausedForLock = true
        persist()
    }

    private func settleAfterReturningToForeground() {
        if stayedPausedForLock {
            stayedPausedForLock = false
            backgroundedAt = nil
            persist()
            return
        }
        // Lock then unlock always comes back active and unlocked. That is not leaving rest.
        if stayedRestingForLock {
            stayedRestingForLock = false
            backgroundedAt = nil
            persist()
            catchUp()
            return
        }
        if phase == .restDue {
            backgroundedAt = nil
            settleRestDue(at: Date())
            return
        }
        if phase == .resting || phase == .restExtra {
            restoreRestAfterLeaveGrace()
            backgroundedAt = nil
            catchUp()
            return
        }
        if phase == .paused {
            if stayedPausedForLock || DeviceLockMonitor.shared.isKeyLocked() {
                stayedPausedForLock = false
                pauseWentToBackground = false
                backgroundedAt = nil
                persist()
                return
            }
            // Still paused after a real background leave that was not a lock: they switched apps.
            if pauseWentToBackground {
                let left = backgroundedAt ?? Date()
                pauseWentToBackground = false
                backgroundedAt = nil
                resume(at: left)
                return
            }
            backgroundedAt = nil
            return
        }
        pauseWentToBackground = false
        backgroundedAt = nil
    }

    private func handleBackgrounded() {
        DeviceLockMonitor.shared.refresh()
        switch phase {
        case .paused:
            pauseWentToBackground = true
            resumeAfterLeavingPause()
        case .resting:
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                keepRestIfLocked()
                return
            }
            warnToReturnToRest()
        case .restExtra:
            if DeviceLockMonitor.shared.isKeyLocked() {
                keepRestIfLocked()
                return
            }
            continueUseAfterLeavingExtraRest()
        case .restDue:
            if DeviceLockMonitor.shared.isKeyLocked() {
                keepRestIfLocked()
            }
        default:
            if DeviceLockMonitor.shared.isKeyLocked() {
                markRestingIfLocked()
            }
        }
    }

    private func restoreRestAfterLeaveGrace() {
        guard phase == .resting, let frozen = restLeaveFrozenRemaining else { return }
        restEndsAt = Date().addingTimeInterval(frozen)
        remaining = frozen
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        persist()
    }

    private func adoptRestLeaveIntoOngoingRest() {
        restoreRestAfterLeaveGrace()
    }

    /// Background Tasks often do not fire while suspended. Returning after 10s must still fail.
    private func failLateReturnFromRestIfNeeded() -> Bool {
        guard phase == .resting else { return false }
        guard restLeftAt != nil || restLeaveFrozenRemaining != nil else { return false }
        DeviceLockMonitor.shared.refresh()
        if DeviceLockMonitor.shared.isKeyLocked() {
            adoptRestLeaveIntoOngoingRest()
            cancelLeaveRestFail()
            stayedRestingForLock = true
            persist()
            return false
        }
        guard let leftAt = restLeftAt, Date().timeIntervalSince(leftAt) >= Self.restLeaveGrace else {
            return false
        }
        failRest(reason: "离开了休息页")
        return true
    }

    private func warnToReturnToRest() {
        guard phase == .resting else { return }
        if restLeftAt == nil {
            restLeftAt = Date()
        }
        if restLeaveFrozenRemaining == nil, let end = restEndsAt {
            restLeaveFrozenRemaining = max(0, end.timeIntervalSinceNow)
            remaining = restLeaveFrozenRemaining ?? remaining
            persist()
        }
        let deadline = (restLeftAt ?? Date()).addingTimeInterval(Self.restLeaveGrace)
        let wait = max(0.05, deadline.timeIntervalSinceNow)
        leaveRestTask?.cancel()
        leaveRestTask = nil
        ParentNotifier.returnToRestNow()
        leaveRestTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            guard phase == .resting else { return }
            DeviceLockMonitor.shared.refresh()
            if DeviceLockMonitor.shared.isKeyLocked() {
                self.adoptRestLeaveIntoOngoingRest()
                self.stayedRestingForLock = true
                self.persist()
                ParentNotifier.cancelReturnToRest()
                return
            }
            guard UIApplication.shared.applicationState == .background else { return }
            failRest(reason: "离开了休息页")
        }
    }

    private func resumeAfterLeavingPause() {
        guard phase == .paused else { return }
        resumedFromPauseInBackground = true
        pauseWentToBackground = false
        stayedPausedForLock = false
        resume(at: backgroundedAt ?? Date())
        persist()
        UserDefaults.standard.synchronize()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if !DeviceLockMonitor.shared.isKeyLocked() {
                self.resumedFromPauseInBackground = false
            }
        }
    }

    private func continueUseAfterLeavingExtraRest() {
        guard phase == .restExtra else { return }
        let startedAt = backgroundedAt ?? Date()
        endExtraRest(grantBonus: true)
        guard remainingDailySeconds > 0 else { return }
        start(at: startedAt)
    }

    /// Killing the process is different from locking the screen: lock keeps the app in memory.
    /// Use time already up always opens rest, never returns to 开始使用.
    private func handleColdLaunch() {
        if stayedRestingForLock, phase == .restDue || phase == .resting || phase == .restExtra {
            catchUp()
            return
        }
        switch phase {
        case .paused:
            if remaining <= 0 || remainingDailySeconds <= 0 {
                enterRestDue(at: Date())
            } else if stayedPausedForLock {
                break
            } else {
                failRest(reason: "暂停时关掉了应用")
            }
        case .working:
            // Wall-clock catch-up. Time already up records 未按时 if late, then opens rest.
            catchUp()
        case .restDue:
            catchUp()
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
                flushUsage(force: true)
                let dueAt = remaining <= 0 ? end : now
                enterRestDue(at: dueAt)
                if DeviceLockMonitor.shared.isKeyLocked() {
                    stayedRestingForLock = true
                    persist()
                }
                beginRestIfPageIsInFront()
                return
            }
        } else if phase == .restDue {
            settleRestDue(at: now)
            beginRestIfPageIsInFront()
            return
        } else if phase == .resting, let end = restEndsAt {
            if let frozen = restLeaveFrozenRemaining {
                remaining = frozen
                return
            }
            remaining = max(0, end.timeIntervalSince(now))
            if remaining <= 0 {
                enterRestExtra()
            }
        } else if phase == .restExtra {
            let extra = max(0, now.timeIntervalSince(restEndsAt ?? now))
            remaining = min(TimeInterval(ExtraRestReward.recordedExtraCap * 60), extra)
        }
    }

    private func settleRestDue(at now: Date) {
        guard phase == .restDue, let deadline = checkInDeadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if now >= deadline {
            recordMissedCheckInIfNeeded()
        }
    }

    /// Late arrival is 未休息 for the parent, but the child still has to rest.
    private func recordMissedCheckInIfNeeded() {
        guard phase == .restDue, !missedCheckInRecorded else { return }
        missedCheckInRecorded = true
        let reason = "到点后超过 2 分钟没有打卡"
        let shouldAlert = report?.skipRest(alertAfter: skippedRestAlertCount, reason: reason) ?? false
        let count = report?.today.skippedRests ?? 1
        ParentNotifier.checkInFailed(reason: reason, count: count)
        if shouldAlert {
            ParentNotifier.skippedRestAlert(
                count: count,
                threshold: skippedRestAlertCount
            )
        }
        persist()
    }

    private func enterRestDue(at dueAt: Date) {
        phase = .restDue
        remaining = Self.checkInGrace
        restDueAt = dueAt
        checkInDeadline = dueAt.addingTimeInterval(Self.checkInGrace)
        workEndsAt = nil
        restEndsAt = nil
        missedCheckInRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        persist()
        maybeNotifyQuota()
        settleRestDue(at: Date())
        if UIApplication.shared.applicationState == .active {
            ParentNotifier.restDueHaptic()
            beginRestIfPageIsInFront()
            if phase == .resting {
                // Add is async. Do not schedule nags that can land after check-in cancels them.
                ParentNotifier.cancelRestNotifications()
            }
            return
        }
        ParentNotifier.scheduleRestNags(from: dueAt)
        ParentNotifier.scheduleMissedCheckIn(at: dueAt.addingTimeInterval(Self.checkInGrace))
    }

    private func scheduleWorkEndAlerts() {
        guard let end = workEndsAt else { return }
        ParentNotifier.scheduleRestDue(at: end, graceSeconds: Self.checkInGrace)
        ParentNotifier.scheduleRestNags(from: end)
        ParentNotifier.scheduleMissedCheckIn(at: end.addingTimeInterval(Self.checkInGrace))
    }

    private func beginRestIfPageIsInFront() {
        guard phase == .restDue else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        checkIn(at: Date())
    }

    /// 去桌面后时间到了，休息页可能在后台被挂上并开始倒计时。回到前台再从满额重计。
    private func restartRestIfItBeganInBackground() {
        guard phase == .resting, !restStartedOnPage, !stayedRestingForLock else { return }
        restEndsAt = Date().addingTimeInterval(restDuration)
        remaining = restDuration
        restStartedOnPage = true
        persist()
    }

    private func checkIn(at date: Date = Date()) {
        guard phase == .restDue else { return }
        clearRestNotifications()
        phase = .resting
        restEndsAt = date.addingTimeInterval(restDuration)
        remaining = restDuration
        restStartedOnPage = true
        persist()
    }

    private func accountWorkingUsage(now: Date = Date(), end: Date? = nil) {
        guard phase == .working, let end = end ?? workEndsAt else { return }
        let remainingWork = max(0, end.timeIntervalSince(now))
        remaining = remainingWork
        let elapsedTotal = max(0, workLength - remainingWork)
        let delta = elapsedTotal - blockUsed
        if delta > 0 {
            blockUsed = elapsedTotal
            pendingUsage += delta
        }
        if pendingUsage > 0, now.timeIntervalSince(lastUsageFlush) >= 2 || remainingWork == 0 {
            flushUsage(force: false)
        }
        maybeNotifyQuota()
    }

    /// Persist the session first, then the report, so a crash cannot add the same minutes twice.
    private func flushUsage(force: Bool) {
        guard pendingUsage > 0 || force else { return }
        let toWrite = pendingUsage
        pendingUsage = 0
        lastUsageFlush = Date()
        persist()
        if toWrite > 0 {
            report?.addUsage(seconds: toWrite)
        }
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
        CheckInFeedback.shared.present(.failure(reason: reason))
        returnToIdle()
    }

    func finishRestAndStartUsing() {
        endExtraRest(grantBonus: true)
        CheckInFeedback.shared.dismiss()
        guard remainingDailySeconds > 0 else { return }
        start()
    }

    func endExtraRest(grantBonus: Bool = true) {
        guard phase == .restExtra else { return }
        let extra = Date().timeIntervalSince(restEndsAt ?? Date())
        let extraMinutes = ExtraRestReward.displayExtraMinutes(max(0, Int(extra / 60)))
        let bonus = grantBonus && rewardExtraRest
            ? ExtraRestReward.bonusMinutes(extra: extraMinutes)
            : 0
        if missedCheckInRecorded {
            report?.grantBonus(bonus)
        } else {
            report?.recordCheckIn(succeeded: true, extraMinutes: extraMinutes, bonusMinutes: bonus)
        }
        returnToIdle()
    }

    private func enterRestExtra() {
        if !missedCheckInRecorded {
            report?.completeRest()
        }
        phase = .restExtra
        remaining = 0
        persist()
        if !missedCheckInRecorded {
            CheckInFeedback.shared.present(.restComplete)
        }
    }

    private func returnToIdle() {
        phase = .idle
        remaining = workDuration
        blockUsed = 0
        workLength = 0
        pendingUsage = 0
        workEndsAt = nil
        restDueAt = nil
        restEndsAt = nil
        checkInDeadline = nil
        stayedRestingForLock = false
        stayedPausedForLock = false
        leftRestForOtherApp = false
        missedCheckInRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        cancelLeaveRestFail()
        RestStoryPlayer.shared.stop()
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
        var stayedPausedForLock: Bool?
        var missedCheckInRecorded: Bool?
        var restStartedOnPage: Bool?
        var workLength: TimeInterval?
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
            stayedRestingForLock: stayedRestingForLock,
            stayedPausedForLock: stayedPausedForLock,
            missedCheckInRecorded: missedCheckInRecorded,
            restStartedOnPage: restStartedOnPage,
            workLength: workLength
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
        stayedPausedForLock = snapshot.stayedPausedForLock ?? false
        missedCheckInRecorded = snapshot.missedCheckInRecorded ?? false
        restStartedOnPage = snapshot.restStartedOnPage ?? false
        if let savedLength = snapshot.workLength, savedLength > 0 {
            workLength = savedLength
        } else {
            workLength = max(0, blockUsed + remaining)
        }
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
