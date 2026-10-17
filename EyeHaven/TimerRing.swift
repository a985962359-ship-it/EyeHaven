import SwiftUI

struct TimerRing: View {
    var progress: Double
    var timeText: String
    var caption: String = "剩余"
    var timeFontSize: CGFloat = 48
    /// 开始使用前可拖动圆环，前后调整计划使用时间
    var scrubEnabled: Bool = false
    var onScrub: ((Double) -> Void)? = nil

    private var lineWidth: CGFloat { HavenLayout.isPad ? 16 : 12 }
    private var scrubProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .stroke(Palette.sage.opacity(0.35), lineWidth: lineWidth)

                progressStroke
                    .rotationEffect(.degrees(-90))

                if scrubEnabled {
                    scrubThumb(in: size)
                }

                VStack(spacing: 4) {
                    Text(timeText)
                        .font(.system(size: timeFontSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .foregroundStyle(Palette.dusk)
                    Text(scrubEnabled ? "拖动可减少时间" : caption)
                        .font(.caption)
                        .foregroundStyle(Palette.pine.opacity(0.7))
                }
                .padding(.horizontal, lineWidth + 10)
                .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(scrubEnabled ? scrubGesture(in: size) : nil)
        }
        // 描边一半在圆外，外扩一点保证显示完整
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scrubEnabled ? "\(timeText) 拖动可减少时间" : "\(caption) \(timeText)")
        .accessibilityHint(scrubEnabled ? "拖动圆环可以减少使用时间" : "")
    }

    @ViewBuilder
    private var progressStroke: some View {
        // 顺时针从正上方开始是「已减掉」；剩下的弧才是剩余使用时间
        let consumed = min(max(1 - scrubProgress, 0), 0.998)
        let trim = Circle().trim(from: consumed, to: 1)
        if HavenLayout.isPad {
            trim.stroke(
                AngularGradient(
                    colors: [Palette.moss, Palette.gold, Palette.pine],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        } else {
            // 手机用单色，角向渐变更吃性能
            trim.stroke(
                Palette.moss,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }

    private func scrubThumb(in size: CGFloat) -> some View {
        // 圆点在「已减掉」的位置（从正上方顺时针）；中间数字是剩余时间
        let consumed = 1 - scrubProgress
        let angle = Angle.degrees(consumed * 360 - 90)
        let radius = size / 2
        return Circle()
            .fill(Palette.foam)
            .frame(width: lineWidth + 10, height: lineWidth + 10)
            .overlay(Circle().stroke(Palette.moss, lineWidth: 3))
            .shadow(color: Palette.pine.opacity(0.2), radius: 3, y: 1)
            .offset(
                x: cos(angle.radians) * radius,
                y: sin(angle.radians) * radius
            )
            .allowsHitTesting(false)
    }

    private func scrubGesture(in size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = Self.progress(from: value.location, size: size)
                onScrub?(p)
            }
    }

    /// 从正上方顺时针 0…1：表示已减掉多少；剩余时间 = 上限 × (1 − 此值)
    private static func progress(from point: CGPoint, size: CGFloat) -> Double {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return min(1, max(0, angle / (2 * .pi)))
    }
}
