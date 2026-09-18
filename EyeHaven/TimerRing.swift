import SwiftUI

struct TimerRing: View {
    var progress: Double
    var timeText: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.sage.opacity(0.35), lineWidth: 16)

            Circle()
                .trim(from: 0, to: min(max(progress, 0.002), 1))
                .stroke(
                    AngularGradient(
                        colors: [Palette.moss, Palette.gold, Palette.pine],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(timeText)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.dusk)
                Text("剩余")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.7))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余时间 \(timeText)")
    }
}
