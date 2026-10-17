import SwiftUI

@main
struct EyeHavenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = RestSession()
    @State private var settings = ParentSettings()
    @State private var report = DailyReport()
    @State private var bedtimeCatalog = BedtimeCatalogStore.shared
    @State private var membership = MembershipStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(report)
                .environment(AppClock.shared)
                .environment(RestStoryPlayer.shared)
                .environment(bedtimeCatalog)
                .environment(membership)
                .onAppear {
                    AppClock.shared.start()
                    RestStoryPlayer.shared.apply(enabled: settings.restStoriesEnabled)
                    session.attach(report: report, settings: settings)
                    bedtimeCatalog.ensureLoaded()
                    // 先用本机目录秒开；后台静默拉网，避免一开 App 主线程卡一下
                    bedtimeCatalog.refreshIfNeeded(showSpinner: false)
                    // 商店查询稍后再跑，别和目录下载抢同一时刻
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        await membership.refresh()
                    }
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
