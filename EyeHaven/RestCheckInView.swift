import SwiftUI

struct RestCheckInView: View {
    @Environment(RestSession.self) private var session
    @Environment(ParentSettings.self) private var settings

    var body: some View {
        ZStack {
            Palette.foam
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text(session.phase == .restExtra ? "可以继续休息" : "现在请休息")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.pine)

                RestTimerLabel(
                    restDuration: session.restDuration,
                    sessionEndDate: session.restAnchorDate,
                    countUp: session.phase == .restExtra
                )
                .frame(maxWidth: .infinity)
                .frame(height: 88)

                Text(statusLine)
                    .font(.title3)
                    .foregroundStyle(Palette.pine)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if settings.rewardExtraRest {
                    Text("多休息 \(ExtraRestReward.extraMinutes) 分钟，下次使用时间增加 \(ExtraRestReward.nextUseMinutes) 分钟")
                        .font(.headline)
                        .foregroundStyle(Palette.gold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Text(hintLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.moss)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if session.phase == .restExtra {
                    Button("开始使用") {
                        session.finishRestAndStartUsing()
                    }
                    .buttonStyle(HavenButtonStyle(filled: true))
                }
            }
            .padding()
        }
        .onAppear {
            session.restPageDidAppear()
        }
    }

    private var statusLine: String {
        switch session.phase {
        case .restDue:
            return "请留在这一页完成打卡"
        case .restExtra:
            return "最少休息已完成。切到其他 App 会开始下一段使用。"
        default:
            return "请把设备放下，留在这一页"
        }
    }

    private var hintLine: String {
        if session.phase == .restExtra {
            return "留在这一页或锁屏才算继续休息。切出去玩会马上开始下一段使用计时。"
        }
        return "请留在这一页。切到其他 App 会记为未休息。锁屏熄屏可以。"
    }
}
