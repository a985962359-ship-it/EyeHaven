import SwiftUI

struct HomeView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @Environment(DailyReport.self) private var report
    @Environment(AppClock.self) private var clock
    @State private var showDistanceGate = false

    var body: some View {
        ZStack {
            background

            ScrollView {
            VStack(spacing: 24) {
                header
                TimerRing(
                    progress: session.progress,
                    timeText: session.phase == .idle
                        ? session.nextUseDuration.clockString
                        : session.remaining(at: clock.now).clockString,
                    caption: session.phase == .idle ? "本次使用" : "剩余"
                )
                .frame(width: 200, height: 200)
                .padding(.vertical, 8)

                Text(session.headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.dusk)

                Text(session.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.pine.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                controls

                if settings.rewardExtraRest, report.nextBonusMinutes > 0 {
                    Text("下次使用奖励 +\(report.nextBonusMinutes) 分钟")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                }

                checkInList
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        .onChange(of: settings.workMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.restMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.dailyLimitMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.skippedRestAlertCount) { _, _ in session.apply(settings) }
        .onChange(of: settings.rewardExtraRest) { _, _ in session.apply(settings) }
        .fullScreenCover(isPresented: $showDistanceGate) {
            DistanceGateView(
                thresholdCm: settings.minimumDistanceCm,
                onPass: {
                    showDistanceGate = false
                    report.recordDistancePass()
                    session.start()
                },
                onCancel: {
                    showDistanceGate = false
                }
            )
        }
    }

    private var checkInList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("打卡记录")
                .font(.headline)
                .foregroundStyle(Palette.dusk)

            Text("今天已用 \(report.today.usedMinutes) / \(settings.dailyLimitMinutes) 分钟 · 未休息 \(report.today.skippedRests) 次")
                .font(.footnote)
                .foregroundStyle(Palette.moss)

            if report.checkIns.isEmpty {
                Text("还没有打卡记录")
                    .font(.subheadline)
                    .foregroundStyle(Palette.pine.opacity(0.7))
            } else {
                ForEach(report.checkIns.prefix(8)) { event in
                    HStack {
                        Text(event.at, format: .dateTime.hour().minute())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Palette.pine)
                        Spacer()
                        Text(event.summary)
                            .font(.footnote)
                            .foregroundStyle(event.succeeded ? Palette.moss : .orange)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var background: some View {
        LinearGradient(
            colors: session.phase == .resting
                ? [Palette.sage.opacity(0.35), Palette.mist]
                : [Palette.foam, Palette.mist],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("EYE HAVEN")
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(Palette.gold)
                Text("护眼使用")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Palette.pine)
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.7))
            }
            Spacer()
        }
    }

    private var headerDetail: String {
        let distance = settings.requireDistanceCheck ? "开始前至少 \(settings.minimumDistanceCm) 厘米" : "未开启测距"
        return "用 \(settings.workMinutes) 分 · 休息 \(settings.restMinutes) 分 · \(distance)"
    }

    private func beginSession() {
        session.attach(report: report)
        session.apply(settings)
        guard !report.isDailyCapReached(dailyLimitMinutes: settings.dailyLimitMinutes) else { return }
        if settings.requireDistanceCheck {
            showDistanceGate = true
        } else {
            session.start()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch session.phase {
            case .working:
                Button("暂停") { session.pause() }
                    .buttonStyle(HavenButtonStyle(filled: false))
            case .paused:
                Button("继续") { session.resume() }
                    .buttonStyle(HavenButtonStyle(filled: true))
            case .restDue, .resting, .restExtra:
                EmptyView()
            case .idle:
                Button("开始使用") { beginSession() }
                    .buttonStyle(HavenButtonStyle(filled: true))
                    .disabled(report.isDailyCapReached(dailyLimitMinutes: settings.dailyLimitMinutes))
            }
        }
    }
}

struct HavenButtonStyle: ButtonStyle {
    var filled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .foregroundStyle(filled ? Palette.foam : Palette.pine)
            .background(
                Capsule()
                    .fill(filled ? Palette.pine : Palette.sage.opacity(0.25))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

#Preview {
    HomeView()
        .environment(RestSession())
        .environment(ParentSettings())
        .environment(DailyReport())
        .environment(AppClock.shared)
}
