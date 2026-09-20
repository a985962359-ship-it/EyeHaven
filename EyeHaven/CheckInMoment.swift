import SwiftUI
import UIKit

enum CheckInMoment: Equatable {
    case restComplete
    case success(extraMinutes: Int, bonusMinutes: Int)
    case failure(reason: String)

    var isSuccess: Bool {
        switch self {
        case .failure: false
        default: true
        }
    }
}

@MainActor
@Observable
final class CheckInFeedback {
    static let shared = CheckInFeedback()

    var moment: CheckInMoment?
    private var afterDismiss: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    func present(_ moment: CheckInMoment, then: (() -> Void)? = nil) {
        dismissTask?.cancel()
        self.moment = moment
        afterDismiss = then
        playHaptic(for: moment)
        let wait: Duration = moment.isSuccess ? .milliseconds(3200) : .milliseconds(3600)
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            // Leaving rest fails in the background. Keep the stamp until they open the app.
            if UIApplication.shared.applicationState != .active {
                return
            }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        moment = nil
        let next = afterDismiss
        afterDismiss = nil
        next?()
    }

    private func playHaptic(for moment: CheckInMoment) {
        let notify = UINotificationFeedbackGenerator()
        notify.prepare()
        switch moment {
        case .restComplete, .success:
            notify.notificationOccurred(.success)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .failure:
            notify.notificationOccurred(.error)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
}

struct CheckInMomentView: View {
    var moment: CheckInMoment
    var onDismiss: () -> Void

    @State private var pop = false
    @State private var burst = false
    @State private var shake = 0

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            if moment.isSuccess {
                confetti
            } else {
                rain
            }

            VStack(spacing: 16) {
                Text(stamp)
                    .font(.caption.weight(.heavy))
                    .tracking(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(stampInk)
                    .background(Capsule().fill(stampFill))
                    .rotationEffect(.degrees(pop ? -8 : 18))
                    .opacity(pop ? 1 : 0)

                Text(emoji)
                    .font(.system(size: HavenLayout.isPad ? 108 : 88))
                    .scaleEffect(pop ? 1 : 0.35)
                    .rotationEffect(.degrees(moment.isSuccess ? (pop ? 0 : -16) : (pop ? 0 : 10)))

                Text(title)
                    .font(HavenLayout.isPad ? .largeTitle.weight(.heavy) : .title.weight(.heavy))
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(HavenLayout.isPad ? .title3 : .body)
                    .multilineTextAlignment(.center)
                    .opacity(0.92)
                    .padding(.horizontal, 20)

                if let prize = prizeLine {
                    Text(prize)
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Palette.gold))
                        .foregroundStyle(Palette.foam)
                        .scaleEffect(pop ? 1 : 0.6)
                }

                Button(moment.isSuccess ? "收下啦" : "我知道了") {
                    onDismiss()
                }
                .buttonStyle(HavenButtonStyle(filled: true))
                .padding(.top, 10)
            }
            .foregroundStyle(Palette.foam)
            .padding(28)
            .frame(maxWidth: HavenLayout.isPad ? 520 : 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(cardFill)
                    .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(moment.isSuccess ? Palette.gold.opacity(0.7) : Color.white.opacity(0.18), lineWidth: 3)
            )
            .scaleEffect(pop ? 1 : 0.82)
            .offset(x: moment.isSuccess ? 0 : CGFloat([-12, 12, -8, 8, 0][shake % 5]))
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                pop = true
            }
            withAnimation(.easeOut(duration: 0.9).delay(0.08)) {
                burst = true
            }
            if !moment.isSuccess {
                Task { @MainActor in
                    for i in 1...5 {
                        try? await Task.sleep(for: .milliseconds(70))
                        shake = i
                    }
                }
            }
        }
        .onTapGesture {
            onDismiss()
        }
        .accessibilityAddTraits(.isModal)
    }

    private var background: some View {
        LinearGradient(
            colors: moment.isSuccess
                ? [Palette.moss, Palette.pine]
                : [Color(red: 0.38, green: 0.12, blue: 0.12), Color(red: 0.18, green: 0.08, blue: 0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardFill: Color {
        moment.isSuccess
            ? Palette.pine.opacity(0.55)
            : Color.black.opacity(0.28)
    }

    private var stamp: String {
        switch moment {
        case .restComplete: "打卡盖章"
        case .success(_, let bonus) where bonus > 0: "奖励入账"
        case .success: "爱眼盖章"
        case .failure: "未完成"
        }
    }

    private var stampFill: Color {
        moment.isSuccess ? Palette.gold : Color(red: 0.45, green: 0.16, blue: 0.14)
    }

    private var stampInk: Color {
        moment.isSuccess ? Palette.pine : Palette.foam
    }

    private var emoji: String {
        switch moment {
        case .restComplete: "😊"
        case .success: "🎉"
        case .failure: "😭"
        }
    }

    private var title: String {
        switch moment {
        case .restComplete: "爱眼成功！"
        case .success(_, let bonus) where bonus > 0: "奖励到手！"
        case .success: "爱眼成功！"
        case .failure: "眼睛在受伤"
        }
    }

    private var detail: String {
        switch moment {
        case .restComplete:
            return "最少休息完成了。可以继续歇，也可以听故事。你保护了自己的眼睛！"
        case .success(let extra, let bonus) where bonus > 0:
            return "多休息了 \(extra) 分钟。下次使用奖励已经准备好了。"
        case .success(let extra, _) where extra > 0:
            return "多休息了 \(extra) 分钟。眼睛会记得你的耐心。"
        case .success:
            return "你完成了休息打卡。眼睛说谢谢你。"
        case .failure(let reason):
            return "\(reason)。这次没有让眼睛真正歇够。"
        }
    }

    private var prizeLine: String? {
        switch moment {
        case .success(_, let bonus) where bonus > 0:
            return "下次使用 +\(bonus) 分钟"
        default:
            return nil
        }
    }

    private var confetti: some View {
        ZStack {
            ForEach(Array(confettiBits.enumerated()), id: \.offset) { index, bit in
                Text(bit.symbol)
                    .font(.system(size: bit.size))
                    .offset(
                        x: burst ? bit.x : 0,
                        y: burst ? bit.y : 20
                    )
                    .opacity(burst ? 0.95 : 0)
                    .rotationEffect(.degrees(burst ? bit.spin : 0))
                    .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(Double(index) * 0.03), value: burst)
            }
        }
        .allowsHitTesting(false)
    }

    private var rain: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Text("💧")
                    .font(.title2)
                    .offset(
                        x: CGFloat((index - 5) * 28),
                        y: burst ? 220 : -80
                    )
                    .opacity(burst ? 0.15 : 0.75)
                    .animation(.easeIn(duration: 1.1).delay(Double(index) * 0.05), value: burst)
            }
        }
        .allowsHitTesting(false)
    }

    private var confettiBits: [(symbol: String, size: CGFloat, x: CGFloat, y: CGFloat, spin: Double)] {
        [
            ("⭐️", 28, -120, -160, -20),
            ("✨", 22, 110, -150, 18),
            ("🌟", 26, -40, -200, 12),
            ("💛", 20, 70, -90, -14),
            ("⭐️", 18, 140, -40, 24),
            ("✨", 24, -150, -50, -10),
            ("🎉", 20, -90, 160, 16),
            ("⭐️", 16, 100, 170, -22),
            ("🌟", 22, 20, 190, 8),
            ("✨", 18, -30, 140, -16)
        ]
    }
}
