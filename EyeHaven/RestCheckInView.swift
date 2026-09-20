import SwiftUI

struct RestCheckInView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @Environment(DailyReport.self) private var report
    @Environment(RestStoryPlayer.self) private var stories
    @State private var showDistanceGate = false

    var body: some View {
        ZStack {
            Palette.foam
                .ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: HavenLayout.isPad ? 32 : 24) {
                        if session.phase == .restExtra, !session.checkInWasLate {
                            Text("😊 爱眼成功")
                                .font(.caption.weight(.heavy))
                                .tracking(1.2)
                                .foregroundStyle(Palette.pine)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Palette.gold.opacity(0.85)))
                        }

                        Text(extraRestTitle)
                            .font(HavenLayout.isPad ? .largeTitle.weight(.bold) : .title.weight(.bold))
                            .foregroundStyle(Palette.pine)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)

                        RestTimerLabel(
                            restDuration: session.restDuration,
                            sessionEndDate: session.restAnchorDate,
                            countUp: session.phase == .restExtra,
                            fontSize: HavenLayout.restTimerFont
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: HavenLayout.restTimerHeight)

                        Text(statusLine)
                            .font(HavenLayout.isPad ? .title2 : .title3)
                            .foregroundStyle(Palette.pine)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if settings.rewardExtraRest {
                            Text("多休息 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多增加 \(ExtraRestReward.nextUseMinutes) 分钟")
                                .font(HavenLayout.isPad ? .title3.weight(.semibold) : .headline)
                                .foregroundStyle(Palette.gold)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Text(hintLine)
                            .font(HavenLayout.isPad ? .body : .subheadline)
                            .foregroundStyle(Palette.moss)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if settings.restStoriesEnabled {
                            storyPanel
                        }

                        if session.phase == .restExtra {
                            Button("开始使用") {
                                beginNextUse()
                            }
                            .buttonStyle(HavenButtonStyle(filled: true))
                        }
                    }
                    .padding(HavenLayout.isPad ? 36 : 20)
                    .frame(maxWidth: HavenLayout.pageMaxWidth)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            session.restPageDidAppear()
            stories.apply(enabled: settings.restStoriesEnabled)
        }
        .onChange(of: settings.restStoriesEnabled) { _, on in
            stories.apply(enabled: on)
        }
        .fullScreenCover(isPresented: $showDistanceGate) {
            DistanceGateView(
                thresholdCm: settings.minimumDistanceCm,
                onPass: {
                    showDistanceGate = false
                    report.recordDistancePass()
                    session.finishRestAndStartUsing()
                },
                onCancel: {
                    showDistanceGate = false
                }
            )
        }
    }

    private func beginNextUse() {
        if settings.requireDistanceCheck {
            showDistanceGate = true
        } else {
            session.finishRestAndStartUsing()
        }
    }

    private var extraRestTitle: String {
        if session.phase == .restExtra {
            return session.checkInWasLate ? "先把休息做完" : "可以继续歇，奖励正在攒"
        }
        return "现在请休息"
    }

    private var statusLine: String {
        switch session.phase {
        case .restDue:
            return "打开这一页才开始休息"
        case .restExtra:
            return session.checkInWasLate
                ? "来晚了，已记为未按时打卡。歇完仍可以开始下一段。"
                : "打卡已经盖章。再多歇一会儿，下次使用可能加时。"
        default:
            return "请把设备放下，留在这一页"
        }
    }

    private var hintLine: String {
        if session.phase == .restExtra {
            return "留在这一页或锁屏才算继续休息。切出去玩会马上开始下一段使用计时。"
        }
        if session.phase == .restDue {
            return settings.restStoriesEnabled
                ? "打开这一页才开始休息。开始后锁屏可以继续歇。切走会马上提醒你回来，10 秒内回来不算失败。想听故事就点播放。"
                : "打开这一页才开始休息。开始后锁屏可以继续歇。切走会马上提醒你回来，10 秒内回来不算失败。"
        }
        return settings.restStoriesEnabled
            ? "休息已经开始。请留在这一页或锁屏。切走会马上提醒你回来，10 秒内回来不算失败。想听故事就点播放。"
            : "休息已经开始。请留在这一页或锁屏。切走会马上提醒你回来，10 秒内回来不算失败。"
    }

    private var storyPanel: some View {
        VStack(spacing: 10) {
            Text("闭上眼睛听")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.gold)
            Text(stories.current?.title ?? "点播放才开始读")
                .font(HavenLayout.isPad ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(Palette.dusk)
                .multilineTextAlignment(.center)
            if let story = stories.current {
                Text("大约 \(story.minutes) 分钟 · 听完自动下一则")
                    .font(.footnote)
                    .foregroundStyle(Palette.pine.opacity(0.7))
            } else {
                Text("不会自动读。想听就点播放，不想听就放下设备休息。")
                    .font(.footnote)
                    .foregroundStyle(Palette.pine.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("下一则") { stories.playNext() }
                    .buttonStyle(HavenButtonStyle(filled: false))
                    .disabled(!stories.isSpeaking && stories.current == nil)
                Button(stories.isPaused || !stories.isSpeaking ? "播放" : "暂停") {
                    stories.togglePause()
                }
                .buttonStyle(HavenButtonStyle(filled: true))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.mist.opacity(0.9))
        )
        .padding(.horizontal, 8)
    }
}
