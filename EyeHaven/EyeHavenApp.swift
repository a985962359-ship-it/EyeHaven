import SwiftUI

@main
struct EyeHavenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = RestSession()
    @State private var settings = ParentSettings()
    @State private var report = DailyReport()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(report)
                .environment(AppClock.shared)
                .environment(RestStoryPlayer.shared)
                .environment(CheckInFeedback.shared)
                .onAppear {
                    AppClock.shared.start()
                    RestStoryPlayer.shared.apply(enabled: settings.restStoriesEnabled)
                    session.attach(report: report, settings: settings)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationPresenter.shared.start()
        Task { @MainActor in
            DeviceLockMonitor.shared.start()
        }
        return true
    }
}
