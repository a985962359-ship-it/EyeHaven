import SwiftUI
import UIKit

/// Drives a countdown with CADisplayLink so SwiftUI view rebuilds cannot freeze the clock.
struct ClockPulseView: UIViewRepresentable {
    var onTick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTick: onTick)
    }

    func makeUIView(context: Context) -> PulseUIView {
        let view = PulseUIView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PulseUIView, context: Context) {
        context.coordinator.onTick = onTick
        uiView.coordinator = context.coordinator
    }

    final class Coordinator {
        var onTick: () -> Void
        init(onTick: @escaping () -> Void) {
            self.onTick = onTick
        }
    }
}

final class PulseUIView: UIView {
    var coordinator: ClockPulseView.Coordinator?
    private var link: CADisplayLink?
    private var lastFire: TimeInterval = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        if lastFire == 0 || link.timestamp - lastFire >= 0.2 {
            lastFire = link.timestamp
            coordinator?.onTick()
        }
    }

    deinit {
        link?.invalidate()
    }
}
