import SwiftUI

struct RestCheckInView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings
    @State private var audio = BedtimeAudioPlayer.shared

    var body: some View {
        ZStack {
            RestBalconyBackground()

            VStack(spacing: 0) {
                Spacer(minLength: HavenLayout.isPad ? 40 : 24)

                VStack(spacing: HavenLayout.isPad ? 28 : 18) {
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
                        .restTextGlow()

                    RestTimerLabel(
                        restDuration: session.restDuration,
                        sessionEndDate: session.restAnchorDate,
                        countUp: session.phase == .restExtra,
                        frozenRemaining: session.restLeaveDisplayFrozen,
                        fontSize: HavenLayout.restTimerFont
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: HavenLayout.restTimerHeight)
                    .restTextGlow()
                }
                .padding(.horizontal, HavenLayout.isPad ? 36 : 20)

                Spacer(minLength: 16)

                // 听故事文字和按钮贴在屏幕下方
                VStack(spacing: 14) {
                    if settings.restStoriesEnabled {
                        storyPanel
                    }
                    if session.phase == .restExtra {
                        Button("开始使用") {
                            // 先回眼睛闹钟首页，再由孩子自己点开始；不直接开计时
                            session.endExtraRest(grantBonus: true)
                        }
                        .buttonStyle(HavenButtonStyle(filled: true))
                    }
                }
                .padding(.horizontal, HavenLayout.isPad ? 36 : 20)
                .padding(.bottom, HavenLayout.isPad ? 36 : 28)
                .frame(maxWidth: HavenLayout.pageMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            session.restPageDidAppear()
        }
    }

    private var extraRestTitle: String {
        if session.phase == .restExtra {
            return session.checkInWasLate ? "先把休息做完" : "可以继续歇，奖励正在攒"
        }
        return "休息中 看窗外远处可以保护眼睛"
    }

    private var storyPanel: some View {
        let story = audio.nowPlayingStory
        return VStack(spacing: 10) {
            Text("闭上眼睛听")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.gold)
                .restTextGlow()
            Text(story?.title ?? "点播放才开始听")
                .font(HavenLayout.isPad ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(Palette.pine)
                .multilineTextAlignment(.center)
                .restTextGlow()
            HStack(spacing: 12) {
                Button("下一则") { audio.playRestNext() }
                    .buttonStyle(HavenButtonStyle(filled: false))
                    .disabled(audio.makeRestListeningQueue().isEmpty)
                Button(audio.isPlaying ? "暂停" : "播放") {
                    audio.toggleRestListening()
                }
                .buttonStyle(HavenButtonStyle(filled: true))
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

private extension View {
    /// 背景图不再蒙白，字用淡白描边保证可读
    func restTextGlow() -> some View {
        shadow(color: .white.opacity(0.95), radius: 3, y: 0)
            .shadow(color: .white.opacity(0.7), radius: 8, y: 1)
    }
}

/// 竖屏用竖版图，横屏用宽图；按焦点裁切，尽量保住光光、小女孩和远景。
private struct RestBalconyBackground: View {
    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(for: geo.size)
            Image(layout.assetName)
                .resizable()
                .frame(width: layout.drawW, height: layout.drawH)
                .position(x: layout.centerX, y: layout.centerY)
        }
        .ignoresSafeArea()
        .clipped()
    }

    private struct Layout {
        let assetName: String
        let drawW: CGFloat
        let drawH: CGFloat
        let centerX: CGFloat
        let centerY: CGFloat
    }

    private static func layout(for size: CGSize) -> Layout {
        let w = size.width
        let h = size.height
        let tall = h > w * 1.05
        // 竖屏 → 竖版图(约9:16)；横屏 → 宽图(约4:3，与资源一致)
        let imgAspect: CGFloat = tall ? (9.0 / 16.0) : (4.0 / 3.0)
        let viewAspect = w / max(h, 1)

        let drawW: CGFloat
        let drawH: CGFloat
        if viewAspect > imgAspect {
            drawW = w
            drawH = w / imgAspect
        } else {
            drawH = h
            drawW = h * imgAspect
        }

        // 焦点落在左下人物+阳台；竖屏略偏下，横屏偏左下兼顾远山夕阳
        let focusX: CGFloat = tall ? 0.42 : 0.38
        let focusY: CGFloat = tall ? 0.78 : 0.70
        let x = min(0, max(w - drawW, w * 0.5 - drawW * focusX))
        let y = min(0, max(h - drawH, h * 0.5 - drawH * focusY))

        return Layout(
            assetName: tall ? "RestBalconyBgPortrait" : "RestBalconyBg",
            drawW: drawW,
            drawH: drawH,
            centerX: x + drawW / 2,
            centerY: y + drawH / 2
        )
    }
}
