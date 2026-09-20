import UIKit
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Let scenePhase catch up after the window exists. Catching up here
        // rebuilds the rest page while UIKit is still opening from the tap.
        completionHandler()
    }
}

enum ParentNotifier {
    private static let restDueId = "eyehaven.rest-due"
    private static let missedCheckInId = "eyehaven.missed-check-in"
    private static let restFinishedId = "eyehaven.rest-finished"
    private static let returnToRestId = "eyehaven.return-to-rest"
    private static let returnToRestSoonId = "eyehaven.return-to-rest.soon"
    private static let restNagPrefix = "eyehaven.rest-nag."
    /// Remind every 2 minutes after work ends, for up to 40 minutes.
    static let restNagInterval: TimeInterval = 120
    private static let restNagCount = 20

    static func requestPermission() {
        NotificationPresenter.shared.start()
    }

    /// Schedule while work is running, so it still fires if the child is in another app.
    static func scheduleRestDue(at date: Date, graceSeconds: TimeInterval) {
        cancelRestDue()
        let delay = max(1, date.timeIntervalSinceNow)
        let minutes = max(1, Int(graceSeconds / 60))
        let content = UNMutableNotificationContent()
        content.title = "该休息打卡了"
        content.body = "请打开 EyeHaven，在 \(minutes) 分钟内留在休息页。iOS 不能把休息页盖在其他 App 上。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: restDueId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleMissedCheckIn(at date: Date) {
        cancelMissedCheckIn()
        let delay = max(1, date.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "未完成休息打卡"
        content.body = "到点后超过 2 分钟没有打开休息页，已记为未休息。请打开 EyeHaven 休息。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: missedCheckInId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// One reminder every 2 minutes until the child opens the rest page. Scheduled in advance so they still fire in another app.
    static func scheduleRestNags(from dueAt: Date) {
        cancelRestNags()
        let center = UNUserNotificationCenter.current()
        for index in 1...restNagCount {
            let fire = dueAt.addingTimeInterval(restNagInterval * TimeInterval(index))
            let delay = fire.timeIntervalSinceNow
            guard delay > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "该休息打卡了"
            content.body = index == 1
                ? "已经过了 2 分钟还没打开休息页。请打开 EyeHaven，不打开会每 2 分钟再提醒一次。"
                : "使用时间已经到了，还在用电子产品。请打开 EyeHaven 休息打卡。"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: restNagId(index),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    static func returnToRestNow() {
        cancelReturnToRest()
        let content = UNMutableNotificationContent()
        content.title = "请回到休息页"
        content.body = "休息还没结束。10 秒内打开 EyeHaven 就不算失败。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let center = UNUserNotificationCenter.current()
        center.add(
            UNNotificationRequest(identifier: returnToRestId, content: content, trigger: nil)
        )
        let soon = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(
            UNNotificationRequest(identifier: returnToRestSoonId, content: content, trigger: soon)
        )
    }

    static func cancelReturnToRest() {
        let ids = [returnToRestId, returnToRestSoonId]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func restDueHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func cancelRestDue() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restDueId])
    }

    static func cancelRestFinished() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restFinishedId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [restFinishedId])
    }

    static func cancelRestNotifications() {
        let ids = [restDueId, missedCheckInId, restFinishedId, returnToRestId, returnToRestSoonId] + restNagIds
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    static func cancelMissedCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [missedCheckInId])
    }

    static func cancelRestNags() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: restNagIds)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: restNagIds)
    }

    private static var restNagIds: [String] {
        (1...restNagCount).map(restNagId)
    }

    private static func restNagId(_ index: Int) -> String {
        "\(restNagPrefix)\(index)"
    }

    static func checkInFailed(reason: String, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "EyeHaven 打卡失败"
        content.body = "\(reason)。今天已有 \(count) 次未完成休息，请打开家长报告查看。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "eyehaven.checkin-failed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func skippedRestAlert(count: Int, threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "EyeHaven 家长报告"
        content.body = "孩子今天已有 \(count) 次没有完成休息，达到你设定的 \(threshold) 次。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "eyehaven.skipped-rest.\(DailyReport.dayKey(for: Date()))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func quotaExhausted(summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "今天的使用额度已用完"
        content.body = summary.replacingOccurrences(of: "\n", with: " · ")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "eyehaven.quota.\(DailyReport.dayKey(for: Date()))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
