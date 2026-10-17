import Foundation
import Observation

@MainActor
@Observable
final class AppClock {
    static let shared = AppClock()

    private(set) var now = Date()
    private var timer: DispatchSourceTimer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 首页只显示「几分」，1 秒刷新足够；0.25 秒会让整页连刷，iPhone 容易卡
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(120))
        timer.setEventHandler { [weak self] in
            self?.now = Date()
        }
        timer.resume()
        self.timer = timer
    }
}
