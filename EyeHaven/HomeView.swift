import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @Environment(DailyReport.self) private var report
    @Environment(AppClock.self) private var clock
    @State private var showDistanceGate = false

    var body: some View {
        ZStack {
            background

            // 一屏看完，不再下拉滚动；详细记录在「家长设置 → 报告」
            VStack(spacing: HavenLayout.isPad ? 20 : 14) {
                compactHeader

                Spacer(minLength: 4)

                // 开始前可拖：家长设定为上限，只能减到更短；开始后不能拖
                TimerRing(
                    progress: ringProgress,
                    timeText: timerText,
                    caption: "剩余",
                    timeFontSize: HavenLayout.isPad ? 56 : 44,
                    scrubEnabled: session.phase == .idle,
                    onScrub: { session.scrubPlannedMinutes(toProgress: $0) }
                )
                .frame(
                    width: HavenLayout.isPad ? 240 : 200,
                    height: HavenLayout.isPad ? 240 : 200
                )
                .padding(10)

                Text(session.headline)
                    .font(HavenLayout.isPad ? .title2.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundStyle(Palette.dusk)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                controls

                if settings.rewardExtraRest, report.nextBonusMinutes > 0 {
                    Text("下次使用奖励 +\(report.nextBonusMinutes) 分钟")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.gold)
                }

                Spacer(minLength: 4)

                todaySummaryBar
            }
            .padding(.horizontal, HavenLayout.isPad ? 36 : 24)
            .padding(.top, HavenLayout.isPad ? 20 : 12)
            .padding(.bottom, HavenLayout.isPad ? 16 : 10)
            .frame(maxWidth: HavenLayout.pageMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .onChange(of: settings.workMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.restMinutes) { _, _ in session.apply(settings) }
        .onChange(of: settings.dailyUseLimit) { _, _ in session.apply(settings) }
        .onChange(of: settings.skippedRestAlertCount) { _, _ in session.apply(settings) }
        .onChange(of: settings.rewardExtraRest) { _, _ in session.apply(settings) }
        .onChange(of: settings.restStoriesEnabled) { _, on in
            RestStoryPlayer.shared.apply(enabled: on)
        }
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

    private var timerText: String {
        if session.phase == .idle {
            return session.nextUseDuration.minutesOnlyString
        }
        return session.remaining(at: clock.now).minutesOnlyString
    }

    /// 圆环按「剩余比例」画：空闲=计划剩余/家长上限；使用中=1−已用比例
    private var ringProgress: Double {
        if session.phase == .idle {
            return session.plannedProgress
        }
        return min(1, max(0, 1 - session.progress))
    }

    /// 顶栏：标题 + 规则一行，不再占大卡片
    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "eye.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Palette.moss, Palette.sage.opacity(0.55))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("护眼计时")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.pine)
                Text(headerDetail)
                    .font(.caption2)
                    .foregroundStyle(Palette.pine.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    /// 今日摘要一条，详细列表去家长报告看
    private var todaySummaryBar: some View {
        let overtime = report.today.overtimeMinutes
        return HStack(spacing: 8) {
            summaryChip(
                title: "已用",
                value: "\(report.today.usedSessions)/\(settings.dailyUseLimit)",
                // 只有超时还不休息超过 5 分钟才记超时，红字写在这里
                redDetail: overtime > 0 ? "超时\(overtime)分" : nil
            )
            summaryChip(title: "休息", value: "\(report.today.completedRests)")
            summaryChip(title: "未休息", value: "\(report.today.skippedRests)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            overtime > 0
                ? "今天已用 \(report.today.usedSessions) 次，上限 \(settings.dailyUseLimit) 次，超时 \(overtime) 分钟，完成休息 \(report.today.completedRests) 次，未休息 \(report.today.skippedRests) 次"
                : "今天已用 \(report.today.usedSessions) 次，上限 \(settings.dailyUseLimit) 次，完成休息 \(report.today.completedRests) 次，未休息 \(report.today.skippedRests) 次"
        )
    }

    private func summaryChip(title: String, value: String, redDetail: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.dusk)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.pine.opacity(0.65))
            if let redDetail {
                Text(redDetail)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.foam.opacity(0.92))
        )
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

    private var headerDetail: String {
        let distance = settings.requireDistanceCheck ? "测距 \(settings.minimumDistanceCm) 厘米" : "未开测距"
        return "用 \(settings.workMinutes) 分 · 休息 \(settings.restMinutes) 分 · \(distance)"
    }

    /// Background this app so the child can use other apps. The use timer keeps running.
    private func leaveToHomeScreen() {
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }

    private func beginSession() {
        session.attach(report: report, settings: settings)
        guard !report.isDailyCapReached(dailyUseLimit: settings.dailyUseLimit) else { return }
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
                Button("去桌面") { leaveToHomeScreen() }
                    .buttonStyle(HavenButtonStyle(filled: true))
            case .paused:
                Button("继续") { session.resume() }
                    .buttonStyle(HavenButtonStyle(filled: true))
            case .restDue, .resting, .restExtra:
                EmptyView()
            case .idle:
                Button("开始使用") { beginSession() }
                    .buttonStyle(HavenButtonStyle(filled: true))
                    .disabled(report.isDailyCapReached(dailyUseLimit: settings.dailyUseLimit))
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
                    .shadow(
                        color: filled ? Palette.pine.opacity(0.22) : .clear,
                        radius: configuration.isPressed ? 2 : 6,
                        y: configuration.isPressed ? 1 : 3
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    HomeView()
        .environment(RestSession())
        .environment(ParentSettings())
        .environment(DailyReport())
        .environment(AppClock.shared)
}
