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
        content.body = "到点后超过 2 分钟没有打开休息页，已记为未休息。"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: missedCheckInId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
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
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restDueId, missedCheckInId, restFinishedId]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [restDueId, missedCheckInId, restFinishedId]
        )
    }

    static func cancelMissedCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [missedCheckInId])
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
