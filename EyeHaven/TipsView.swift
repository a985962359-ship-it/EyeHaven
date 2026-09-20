import SwiftUI

struct EyeTip: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

struct TipsView: View {
    private let tips: [EyeTip] = [
        .init(
            id: "pace",
            title: "用一会儿，歇一会儿",
            detail: "使用时间到了，请打开休息页。打开这一页才开始休息。超过 2 分钟再打开会记为未按时打卡，但仍要歇完。休息开始后请留在该页或锁屏。切走会马上提醒你回来，10 秒内回来不算失败，超过 10 秒再回来会记失败。",
            symbol: "clock"
        ),
        .init(
            id: "blink",
            title: "多眨眼",
            detail: "盯屏幕时眨眼会变少。有意识地缓慢眨眼，保持泪膜稳定。",
            symbol: "drop"
        ),
        .init(
            id: "screen",
            title: "屏幕略低于视线",
            detail: "显示器上沿接近或略低于眼平线，减少睁眼幅度和泪液蒸发。",
            symbol: "display"
        ),
        .init(
            id: "light",
            title: "光线柔和",
            detail: "避免屏幕和周围环境反差过大，也不要对着刺眼窗口。",
            symbol: "sun.haze"
        ),
        .init(
            id: "walk",
            title: "站起来走动",
            detail: "护眼之外，起来活动一下肩颈，整个人都会轻松许多。",
            symbol: "figure.walk"
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("把眼睛安放在更舒服的节奏里。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.pine.opacity(0.75))
                        .padding(.bottom, 4)

                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: tip.symbol)
                                .font(.title2)
                                .foregroundStyle(Palette.moss)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(tip.title)
                                    .font(.headline)
                                    .foregroundStyle(Palette.dusk)
                                Text(tip.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.pine.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Palette.foam)
                        )
                    }
                }
                .padding(HavenLayout.isPad ? 28 : 16)
                .frame(maxWidth: HavenLayout.pageMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.mist.ignoresSafeArea())
            .navigationTitle("护眼提示")
        }
    }
}

#Preview {
    TipsView()
}
