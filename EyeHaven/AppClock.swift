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
        timer.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.now = Date()
        }
        timer.resume()
        self.timer = timer
    }
}
