import SwiftUI

struct RootView: View {
    @Environment(RestSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.showsRestPage {
            RestCheckInView()
                .id("rest-screen")
            } else {
                mainTabs
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
        }
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
}
