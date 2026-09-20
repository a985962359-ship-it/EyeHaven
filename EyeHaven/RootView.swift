import SwiftUI

struct RootView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @Environment(CheckInFeedback.self) private var feedback
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if session.showsRestPage {
                RestCheckInView()
                    .id("rest-screen")
                } else {
                    mainTabs
                }
            }
            if let moment = feedback.moment {
                CheckInMomentView(moment: moment) {
                    feedback.dismiss()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: feedback.moment)
        .onAppear {
            session.apply(settings)
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
        }
        .onChange(of: settings.workMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.restMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.dailyLimitMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.skippedRestAlertCount) { _, _ in session.apply(settings) }
        .onChange(of: settings.rewardExtraRest) { _, _ in session.apply(settings) }
    }

    private var mainTabs: some View {
        TabView {
            HomeView()
                .tabItem { Label("使用", systemImage: "eye") }
            TipsView()
                .tabItem { Label("护眼", systemImage: "leaf") }
            ParentAreaView()
                .tabItem { Label("家长", systemImage: "lock") }
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
        .environment(CheckInFeedback.shared)
}
