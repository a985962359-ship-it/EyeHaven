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

    /// 仅侧键/密码锁屏。iPad 切桌面、切游戏时 blanked/display 会误报，不能用来判断「在歇着」。
    func isLockOrScreenOff() -> Bool {
        isKeyLocked()
    }

    /// Screen is on and the device is not locked — the user is in another app.
    func isUsingAnotherApp() -> Bool {
        guard UIApplication.shared.applicationState != .active else { return false }
        return !isKeyLocked()
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
    /// Parent can set reward up to this many minutes each time.
    static let maxBonusMinutes = 10
    static let recordedExtraCap = 99

    static func bonusMinutes(extra: Int, maxBonus: Int) -> Int {
        guard extra >= extraMinutes else { return 0 }
        let cap = min(maxBonusMinutes, max(0, maxBonus))
        return min(cap, extra / 2)
    }

    static func displayExtraMinutes(_ extra: Int) -> Int {
        min(recordedExtraCap, max(0, extra))
    }
}

/// Session rules — keep these when changing this file:
/// 1. Rest normally starts when the rest page is in front and the app is active.
/// 2. 侧键真锁屏算休息：到点不弹提醒；从到点时刻起算休息（可静默进入 resting）。
/// 3. restDue + home / other app is expected. Do not fail.
/// 4. Leave-fail only while `.resting`, after 10 seconds away. Notify immediately. Extra-rest leave starts the next use.
/// 5. More than 2 minutes late: record 未按时, still rest, no celebration.
/// 6. Kill: working / restDue / pause(without lock) / resting(未满) → 打卡失败；休息已满则直接完成。
/// 7. Pause: background resumes immediately; real lockstate re-pauses. Rest: background warns and freezes.
/// 8. 故事页 / TipsView / BedtimeStory 只展示文字。禁止接到本文件、通知、朗读或锁屏。
@MainActor
@Observable
final class RestSession {
    static let checkInGrace: TimeInterval = 120
    /// 超时后仍不休息，超过此时长才把超时分钟记进首页「已用」红字
    static let overtimeRecordAfter: TimeInterval = 5 * 60
    static let restLeaveGrace: TimeInterval = 10

    var workMinutes: Int
    /// 开始前可拖圆环在此范围内减少：1…workMinutes（家长设定为上限，不能超过）
    private(set) var plannedWorkMinutes: Int
    var restMinutes: Int
    var dailyUseLimit: Int
    var skippedRestAlertCount: Int
    var rewardExtraRest: Bool
    var rewardBonusMinutes: Int

    init() {
        let settings = ParentSettings()
        workMinutes = settings.workMinutes
        plannedWorkMinutes = settings.workMinutes
        restMinutes = settings.restMinutes
        dailyUseLimit = settings.dailyUseLimit
        skippedRestAlertCount = settings.skippedRestAlertCount
        rewardExtraRest = settings.rewardExtraRest
        rewardBonusMinutes = settings.rewardBonusMinutes
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
    private var leavePauseTask: Task<Void, Never>?
    private var deviceLocked = false
    private var didObserveLock = false
    private var backgroundedAt: Date?
    private var resumedFromPauseInBackground = false
    private var pauseWentToBackground = false
    private var stayedPausedForLock = false
    private var stayedRestingForLock = false
    /// 使用中侧键锁屏：取消「该休息」预约通知；到点后按锁屏休息入账，不弹窗
    private var suppressRestAlertsWhileLocked = false
    private var leftRestForOtherApp = false
    private var missedCheckInRecorded = false
    /// 本段到点后「超时不休息≥5分钟」是否已记入日报
    private var overtimeRecorded = false
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

    var remainingDailyUses: Int {
        report?.remainingUses(dailyUseLimit: dailyUseLimit) ?? dailyUseLimit
    }

    /// Next work block if the child taps 开始使用 now.
    var nextUseDuration: TimeInterval {
        let bonus = rewardExtraRest ? (report?.nextBonusMinutes ?? 0) : 0
        let minutes = plannedWorkMinutes + bonus
        return TimeInterval(minutes * 60)
    }

    /// 空闲圆环进度：相对家长上限，满环 = 家长设定的最多分钟。
    var plannedProgress: Double {
        let maxM = max(1, workMinutes)
        return Double(plannedWorkMinutes) / Double(maxM)
    }

    /// 开始使用前拖圆环：顺时针表示已减掉的时间，中间显示剩余（不能超过家长上限）。
    func scrubPlannedMinutes(toProgress progress: Double) {
        guard phase == .idle else { return }
        let maxM = max(1, workMinutes)
        // progress：从正上方顺时针 0…1 = 已减掉的比例；剩余 = 上限 × (1 − 已减)
        let consumed = min(1, max(0, progress))
        let minutes = max(1, min(maxM, Int(((1 - consumed) * Double(maxM)).rounded())))
        guard plannedWorkMinutes != minutes else { return }
        plannedWorkMinutes = minutes
        remaining = TimeInterval(minutes * 60)
    }

    var headline: String {
        switch phase {
        case .idle:
            remainingDailyUses <= 0 ? "今天的使用次数用完了" : "准备开始"
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
            remainingDailyUses <= 0
                ? "今天次数用完了。报告已写给家长。"
                : idleSubtitle
        case .working:
            rewardExtraRest
                ? "计时已开始。可以切到其他 App，时间会继续走。划掉 App 会记到眼睛休息记录。休息后再多歇 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多加 \(rewardBonusMinutes) 分钟。"
                : "计时已开始。可以切到其他 App，时间会继续走。划掉 App 会记到眼睛休息记录。"
        case .paused:
            "暂停中。请留在这一页或锁屏。切到其他 App 会马上继续计时，划掉 App 记为未打卡。"
        case .restDue:
            "请打开休息页打卡。不打开会每 2 分钟提醒。超过 2 分钟记为未休息。锁屏算休息，锁屏时不弹提醒。"
        case .resting:
            "休息已开始。请留在这一页或锁屏。锁屏算在休息。切走会马上提醒你回来，10 秒内回来不算失败，超过 10 秒再回来会记失败。"
        case .restExtra:
            extraRestSubtitle
        }
    }

    private var idleSubtitle: String {
        let left = max(0, remainingDailyUses)
        let dailyText = "今天还可使用 \(left) 次。"
        let bonus = rewardExtraRest ? (report?.nextBonusMinutes ?? 0) : 0
        let bonusText = bonus > 0 ? "下次使用将多 \(bonus) 分钟。" : ""
        return "用 \(workMinutes) 分钟，休息 \(restMinutes) 分钟。\(dailyText)\(bonusText)"
    }

    private var extraRestSubtitle: String {
        if rewardExtraRest {
            return "最少休息已完成。留在这一页再多休息 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多增加 \(rewardBonusMinutes) 分钟。切到其他 App 会开始下一段使用计时。"
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
        ParentNotifier.cancelQuotaNags()
        maybeNotifyQuota()
    }

    func apply(_ settings: ParentSettings) {
        let previousMax = workMinutes
        workMinutes = settings.workMinutes
        restMinutes = settings.restMinutes
        dailyUseLimit = settings.dailyUseLimit
        skippedRestAlertCount = settings.skippedRestAlertCount
        rewardExtraRest = settings.rewardExtraRest
        rewardBonusMinutes = min(
            ExtraRestReward.maxBonusMinutes,
            max(1, settings.rewardBonusMinutes)
        )
        // 家长改了上限 → 回到上限；否则夹在 1…新上限（不能超过家长设定）
        if workMinutes != previousMax {
            plannedWorkMinutes = workMinutes
        } else {
            plannedWorkMinutes = min(plannedWorkMinutes, workMinutes)
        }
        plannedWorkMinutes = max(1, min(workMinutes, plannedWorkMinutes))
        if phase == .idle {
            remaining = TimeInterval(plannedWorkMinutes * 60)
            blockUsed = 0
        }
        ParentNotifier.cancelQuotaNags()
        maybeNotifyQuota()
    }

    func start(at date: Date = Date()) {
        guard phase == .idle else { return }
        guard report?.consumeUseSession(dailyUseLimit: dailyUseLimit) == true else { return }
        phase = .working
        blockUsed = 0
        let bonus = rewardExtraRest ? (report?.consumeBonus() ?? 0) : 0
        let minutes = max(1, min(workMinutes, plannedWorkMinutes)) + bonus
        let length = TimeInterval(minutes * 60)
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
        overtimeRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        RestStoryPlayer.shared.stop()
        BedtimeAudioPlayer.shared.stop()
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
        // 次数在开始时已扣；暂停恢复只按本段剩余时间继续
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
            // 只有侧键真锁屏才当「在歇着」。iPad 切桌面/游戏不能当锁屏。
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                cancelLeaveRestFail()
                markRestingIfLocked()
                if phase == .paused {
                    stayedPausedForLock = true
                }
            }
            if phase == .paused || phase == .restDue || phase == .resting || phase == .restExtra {
                backgroundedAt = Date()
            }
            persist()
        case .background:
            backgroundedAt = Date()
            // 关掉 / 切走软件后，不要再推「没有使用次数」
            ParentNotifier.cancelQuotaNags()
            if phase == .working {
                catchUp()
            }
            flushUsage(force: true)
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                cancelLeaveRestFail()
                markRestingIfLocked()
                if phase == .paused {
                    stayedPausedForLock = true
                    pauseWentToBackground = false
                }
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
                pauseWentToBackground = false
                persist()
            }
            keepPauseIfLocked()
            return
        }
        // 解锁：若还在使用中，把「到点提醒」重新约上（锁屏期间已取消）
        if phase == .working {
            suppressRestAlertsWhileLocked = false
            scheduleWorkEndAlerts()
            return
        }
        // 解锁后若仍在「该休息」且还没因锁屏开休，再继续催
        if phase == .restDue, let due = restDueAt {
            ParentNotifier.scheduleRestNags(from: due)
            if let deadline = checkInDeadline {
                ParentNotifier.scheduleMissedCheckIn(at: deadline)
            }
        }
    }

    private func markRestingIfLocked() {
        keepRestIfLocked()
    }

    /// 侧键真锁屏：算在休息；取消催促通知；若已到点则立刻开休。
    private func keepRestIfLocked() {
        guard DeviceLockMonitor.shared.isKeyLocked() else { return }
        deviceLocked = true
        leftRestForOtherApp = false

        if phase == .working {
            // 使用中锁屏：别让锁屏弹出「该休息打卡」；到点后由 enterRestDue 静默开休
            suppressRestAlertsWhileLocked = true
            ParentNotifier.cancelRestNotifications()
            persist()
            return
        }

        if phase == .restDue {
            stayedRestingForLock = true
            suppressRestAlertsWhileLocked = true
            ParentNotifier.cancelRestNotifications()
            checkIn(at: Date())
            persist()
            return
        }

        if phase == .resting || phase == .restExtra {
            stayedRestingForLock = true
            ParentNotifier.cancelReturnToRest()
            ParentNotifier.cancelRestNags()
            ParentNotifier.cancelMissedCheckIn()
            ParentNotifier.cancelRestDue()
            persist()
        }
    }

    private func cancelLeaveRestFail() {
        leaveRestTask?.cancel()
        leaveRestTask = nil
        leavePauseTask?.cancel()
        leavePauseTask = nil
        ParentNotifier.cancelReturnToRest()
    }

    /// 暂停：只有侧键真锁屏才重新暂停。切桌面/游戏必须继续计时。
    private func keepPauseIfLocked() {
        guard DeviceLockMonitor.shared.isKeyLocked() else { return }
        leavePauseTask?.cancel()
        leavePauseTask = nil
        if phase == .working, resumedFromPauseInBackground {
            pause()
            resumedFromPauseInBackground = false
            stayedPausedForLock = true
            persist()
            return
        }
        if phase == .paused {
            stayedPausedForLock = true
            pauseWentToBackground = false
            persist()
        }
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
            // 规则 7：切后台立刻继续计时；只有侧键真锁屏才保持暂停
            if DeviceLockMonitor.shared.isKeyLocked() {
                stayedPausedForLock = true
                pauseWentToBackground = false
                persist()
                return
            }
            pauseWentToBackground = true
            resumeAfterLeavingPause()
        case .resting:
            if DeviceLockMonitor.shared.isKeyLocked() {
                adoptRestLeaveIntoOngoingRest()
                keepRestIfLocked()
                cancelLeaveRestFail()
                return
            }
            deferRestLeaveDecision()
        case .restExtra:
            if DeviceLockMonitor.shared.isKeyLocked() {
                keepRestIfLocked()
                return
            }
            deferExtraRestLeaveDecision()
        case .restDue:
            if DeviceLockMonitor.shared.isKeyLocked() {
                keepRestIfLocked() // 锁屏即开休并取消催促
            }
        case .working:
            if DeviceLockMonitor.shared.isKeyLocked() {
                keepRestIfLocked() // 取消到点锁屏弹窗
            }
        default:
            break
        }
    }

    /// 稍等侧键锁屏信号；没锁屏且不在前台 → 提醒回休息页（iPad 切桌面/游戏也要催）。
    private func deferRestLeaveDecision() {
        leaveRestTask?.cancel()
        leaveRestTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            guard phase == .resting else { return }
            DeviceLockMonitor.shared.refresh()
            if DeviceLockMonitor.shared.isKeyLocked() {
                self.adoptRestLeaveIntoOngoingRest()
                self.keepRestIfLocked()
                self.cancelLeaveRestFail()
                return
            }
            if UIApplication.shared.applicationState != .active {
                self.warnToReturnToRest()
            }
        }
    }

    private func deferExtraRestLeaveDecision() {
        leaveRestTask?.cancel()
        leaveRestTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            guard phase == .restExtra else { return }
            DeviceLockMonitor.shared.refresh()
            if DeviceLockMonitor.shared.isKeyLocked() {
                self.keepRestIfLocked()
                return
            }
            if UIApplication.shared.applicationState != .active {
                self.continueUseAfterLeavingExtraRest()
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
        DeviceLockMonitor.shared.refresh()
        // 只有真锁屏不催；切桌面/游戏必须催
        if DeviceLockMonitor.shared.isKeyLocked() {
            adoptRestLeaveIntoOngoingRest()
            keepRestIfLocked()
            cancelLeaveRestFail()
            return
        }
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
            guard UIApplication.shared.applicationState != .active else { return }
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
        guard remainingDailyUses > 0 else { return }
        start(at: startedAt)
    }

    /// Killing the process is different from locking the screen: lock keeps the app in memory.
    /// Use time already up always opens rest, never returns to 开始使用.
    private func handleColdLaunch() {
        if stayedRestingForLock, phase == .restDue || phase == .resting || phase == .restExtra {
            // 划掉后再开：休息时长已过完 → 直接回主界面，不再进休息页
            if phase == .resting, let end = restEndsAt, Date() >= end {
                finishRestAfterAwayBeyondDuration()
                return
            }
            catchUp()
            return
        }
        switch phase {
        case .paused:
            if remaining <= 0 {
                enterRestDue(at: Date())
            } else if stayedPausedForLock {
                break
            } else {
                failRest(reason: "暂停时关掉了应用")
            }
        case .working:
            // 必须先看墙钟 workEndsAt：快照里的 remaining 可能还没结算，已过点却仍 > 0
            if let end = workEndsAt, Date() >= end {
                catchUp()
            } else if remaining <= 0 {
                catchUp()
            } else {
                // 划掉软件：记到打卡记录，并结束这一段
                failRest(reason: "使用时关掉了应用")
            }
        case .restDue:
            failRest(reason: "该休息时关掉了应用")
        case .resting:
            if let end = restEndsAt, Date() >= end {
                // 划掉程序后，回来时休息时间已过 → 不进休息页
                finishRestAfterAwayBeyondDuration()
            } else {
                failRest(reason: "休息时关掉了应用")
            }
        case .restExtra:
            // 划掉 App 再开：结算多休息奖励后回主界面，不要自动开下一段使用
            endExtraRest(grantBonus: true)
        default:
            catchUp()
        }
    }

    /// 离开 App 期间休息倒计时已走完：记完成，回主界面。
    private func finishRestAfterAwayBeyondDuration() {
        ParentNotifier.cancelRestNotifications()
        ParentNotifier.cancelReturnToRest()
        cancelLeaveRestFail()
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        if !missedCheckInRecorded {
            report?.completeRest()
        }
        // 离开期间若已超过最少休息，按多休息规则给奖励（不展示额外休息页）
        if let end = restEndsAt {
            let extra = Date().timeIntervalSince(end)
            let extraMinutes = ExtraRestReward.displayExtraMinutes(max(0, Int(extra / 60)))
            let bonus = rewardExtraRest
                ? ExtraRestReward.bonusMinutes(extra: extraMinutes, maxBonus: rewardBonusMinutes)
                : 0
            if missedCheckInRecorded {
                report?.grantBonus(bonus)
            } else if bonus > 0 || extraMinutes > 0 {
                report?.recordCheckIn(succeeded: true, extraMinutes: extraMinutes, bonusMinutes: bonus)
            } else {
                report?.recordCheckIn(succeeded: true, extraMinutes: 0, bonusMinutes: 0)
            }
        }
        returnToIdle()
    }

    func catchUp() {
        displayNow = Date()
        guard phase != .idle, phase != .paused else { return }
        let now = displayNow
        if phase == .working, let end = workEndsAt {
            accountWorkingUsage(now: now, end: end)
            if remaining <= 0 {
                flushUsage(force: true)
                enterRestDue(at: end)
                // enterRestDue 在锁屏时已静默开休；未锁屏再尝试前台打卡
                if phase == .restDue {
                    beginRestIfPageIsInFront()
                }
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
        recordOvertimeIfNeeded(at: now)
    }

    /// 到点后仍不休息满 5 分钟，才把这段超时记进首页「已用」红字（休息页不显示）。
    private func recordOvertimeIfNeeded(at now: Date = Date()) {
        guard phase == .restDue, let due = restDueAt, !overtimeRecorded else { return }
        let overdue = now.timeIntervalSince(due)
        guard overdue >= Self.overtimeRecordAfter else { return }
        overtimeRecorded = true
        report?.addOvertime(seconds: overdue)
        persist()
    }

    /// Late arrival is 未休息 for the parent, but the child still has to rest.
    private func recordMissedCheckInIfNeeded() {
        guard phase == .restDue, !missedCheckInRecorded else { return }
        missedCheckInRecorded = true
        // 已入账则取消预约的「未完成打卡」通知，避免和应用内失败通知叠两条
        ParentNotifier.cancelMissedCheckIn()
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
        overtimeRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        persist()
        maybeNotifyQuota()

        DeviceLockMonitor.shared.refresh()
        let lockedNow = DeviceLockMonitor.shared.isKeyLocked()
        // 锁屏期间到点（或锁屏后才发现已过点）：从到点起算休息，不弹任何提醒、不记「未打卡」
        if lockedNow || suppressRestAlertsWhileLocked {
            stayedRestingForLock = true
            suppressRestAlertsWhileLocked = false
            ParentNotifier.cancelRestNotifications()
            checkIn(at: dueAt)
            catchUp()
            return
        }

        settleRestDue(at: Date())

        // 到点立刻提醒（前台也出横幅）。先清掉开计时时预约的同一条，避免响两次。
        ParentNotifier.cancelRestDue()
        ParentNotifier.notifyRestDueNow(graceSeconds: Self.checkInGrace)

        if UIApplication.shared.applicationState == .active {
            ParentNotifier.restDueHaptic()
            beginRestIfPageIsInFront()
            if phase == .resting {
                // 只清后续催促，保留刚弹出的「该休息」横幅，别整组 cancel 掉
                ParentNotifier.cancelRestNags()
                ParentNotifier.cancelMissedCheckIn()
            } else {
                ParentNotifier.scheduleRestNags(from: dueAt)
                ParentNotifier.scheduleMissedCheckIn(at: dueAt.addingTimeInterval(Self.checkInGrace))
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
        returnToIdle()
    }

    func finishRestAndStartUsing() {
        endExtraRest(grantBonus: true)
        guard remainingDailyUses > 0 else { return }
        start()
    }

    func endExtraRest(grantBonus: Bool = true) {
        guard phase == .restExtra else { return }
        let extra = Date().timeIntervalSince(restEndsAt ?? Date())
        let extraMinutes = ExtraRestReward.displayExtraMinutes(max(0, Int(extra / 60)))
        let bonus = grantBonus && rewardExtraRest
            ? ExtraRestReward.bonusMinutes(extra: extraMinutes, maxBonus: rewardBonusMinutes)
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
    }

    private func returnToIdle() {
        phase = .idle
        // 下一段重新从家长上限开始，孩子仍可再往下拖减
        plannedWorkMinutes = max(1, workMinutes)
        remaining = TimeInterval(plannedWorkMinutes * 60)
        blockUsed = 0
        workLength = 0
        pendingUsage = 0
        workEndsAt = nil
        restDueAt = nil
        restEndsAt = nil
        checkInDeadline = nil
        stayedRestingForLock = false
        stayedPausedForLock = false
        suppressRestAlertsWhileLocked = false
        leftRestForOtherApp = false
        missedCheckInRecorded = false
        overtimeRecorded = false
        restStartedOnPage = false
        restLeaveFrozenRemaining = nil
        restLeftAt = nil
        cancelLeaveRestFail()
        RestStoryPlayer.shared.stop()
        BedtimeAudioPlayer.shared.stop()
        persist()
        maybeNotifyQuota()
    }

    private func maybeNotifyQuota() {
        // 关掉 App 后不再反复催「没有次数」；只在刚用完时通知家长一次
        ParentNotifier.cancelQuotaNags()
        guard remainingDailyUses <= 0 else { return }
        guard report?.markQuotaExhausted() == true else { return }
        ParentNotifier.quotaExhausted(
            summary: report?.summaryText(
                dailyUseLimit: dailyUseLimit,
                alertAfter: skippedRestAlertCount
            ) ?? "今天的使用次数已用完。"
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
        var overtimeRecorded: Bool?
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
            overtimeRecorded: overtimeRecorded,
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
        overtimeRecorded = snapshot.overtimeRecorded ?? false
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

    /// 使用页倒计时：只显示分钟（有剩余时向上取整，最后不到 1 分钟仍显示 1 分）
    var minutesOnlyString: String {
        let seconds = max(0, self)
        if seconds <= 0 { return "0分" }
        let minutes = Int(ceil(seconds / 60))
        return "\(minutes)分"
    }
}
