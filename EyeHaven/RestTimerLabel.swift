import SwiftUI
import UIKit

struct RestTimerLabel: UIViewRepresentable {
    var restDuration: TimeInterval
    var sessionEndDate: Date?
    var countUp: Bool

    func makeUIView(context: Context) -> RestTimerUIView {
        let view = RestTimerUIView()
        view.apply(restDuration: restDuration, sessionEndDate: sessionEndDate, countUp: countUp)
        return view
    }

    func updateUIView(_ uiView: RestTimerUIView, context: Context) {
        uiView.apply(restDuration: restDuration, sessionEndDate: sessionEndDate, countUp: countUp)
    }

    static func dismantleUIView(_ uiView: RestTimerUIView, coordinator: ()) {
        uiView.stop()
    }
}

/// CADisplayLink retains its target; keep the view off that retain so SwiftUI can tear the label down when opening from a notification.
private final class DisplayLinkProxy: NSObject {
    weak var owner: RestTimerUIView?

    @objc func tick() {
        owner?.tick()
    }
}

final class RestTimerUIView: UIView {
    private let label = UILabel()
    private let proxy = DisplayLinkProxy()
    private var link: CADisplayLink?
    /// Frozen when first set so SwiftUI updates cannot restart the countdown.
    private var lockedEndDate: Date?
    private var countUp = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        proxy.owner = self
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .light)
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.12, green: 0.18, blue: 0.17, alpha: 1)
        label.adjustsFontSizeToFitWidth = true
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(restDuration: TimeInterval, sessionEndDate: Date?, countUp: Bool) {
        self.countUp = countUp
        if lockedEndDate == nil {
            lockedEndDate = sessionEndDate ?? Date().addingTimeInterval(max(1, restDuration))
        }
        tick()
        if window != nil {
            start()
        }
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else {
            start()
        }
    }

    fileprivate func tick() {
        guard let end = lockedEndDate else { return }
        let value: TimeInterval
        if countUp {
            value = max(0, Date().timeIntervalSince(end))
        } else {
            value = max(0, end.timeIntervalSinceNow)
        }
        let total = Int(value.rounded())
        label.text = String(format: "%d:%02d", total / 60, total % 60)
    }

    deinit {
        link?.invalidate()
    }
}
