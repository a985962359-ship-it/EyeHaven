import SwiftUI

struct RootView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @Environment(MembershipStore.self) private var membership
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var membership = membership
        Group {
            if session.showsRestPage {
                RestCheckInView()
                    .id("rest-screen")
            } else {
                mainTabs
            }
        }
        .sheet(isPresented: $membership.showPaywall) {
            MembershipPaywallSheet()
                .environment(membership)
        }
        .onAppear {
            session.apply(settings)
            // 打开 App 时先松一次音频，避免上次占着导致 iPad 没声
            BedtimeAudioPlayer.shared.releaseSessionIfIdle()
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
            if newPhase == .background || newPhase == .active {
                // 切走或回到前台且没在播时，交还系统声音（不碰计时逻辑）
                BedtimeAudioPlayer.shared.releaseSessionIfIdle()
            }
        }
        .onChange(of: settings.workMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.restMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.dailyUseLimit) { _, _ in session.apply(settings) }
        .onChange(of: settings.skippedRestAlertCount) { _, _ in session.apply(settings) }
        .onChange(of: settings.rewardExtraRest) { _, _ in session.apply(settings) }
        .onChange(of: settings.rewardBonusMinutes) { _, _ in session.apply(settings) }
    }

    private var mainTabs: some View {
        TabView {
            HomeView()
                .tabItem { Label("眼睛闹钟", systemImage: "eye.circle.fill") }
            TipsView()
                .tabItem { Label("睡前故事", systemImage: "books.vertical.fill") }
            ParentAreaView()
                .tabItem { Label("家长设置", systemImage: "person.crop.circle.fill") }
        }
        .tint(Palette.moss)
        .preferredColorScheme(.light)
    }
}

#Preview {
    RootView()
        .environment(RestSession())
        .environment(ParentSettings())
        .environment(DailyReport())
        .environment(AppClock.shared)
        .environment(RestStoryPlayer.shared)
        .environment(BedtimeCatalogStore.shared)
        .environment(MembershipStore.shared)
}
