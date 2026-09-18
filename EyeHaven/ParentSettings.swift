import Foundation
import Observation

@Observable
final class ParentSettings {
    private enum Key {
        static let workMinutes = "parent.workMinutes"
        static let restMinutes = "parent.restMinutes"
        static let dailyLimitMinutes = "parent.dailyLimitMinutes"
        static let minimumDistanceCm = "parent.minimumDistanceCm"
        static let requireDistanceCheck = "parent.requireDistanceCheck"
        static let skippedRestAlertCount = "parent.skippedRestAlertCount"
        static let rewardExtraRest = "parent.rewardExtraRest"
        static let pin = "parent.pin"
    }

    var workMinutes: Int {
        didSet { persist(workMinutes, Key.workMinutes) }
    }

    var restMinutes: Int {
        didSet { persist(restMinutes, Key.restMinutes) }
    }

    var dailyLimitMinutes: Int {
        didSet { persist(dailyLimitMinutes, Key.dailyLimitMinutes) }
    }

    var minimumDistanceCm: Int {
        didSet { persist(minimumDistanceCm, Key.minimumDistanceCm) }
    }

    var requireDistanceCheck: Bool {
        didSet { UserDefaults.standard.set(requireDistanceCheck, forKey: Key.requireDistanceCheck) }
    }

    var skippedRestAlertCount: Int {
        didSet { persist(skippedRestAlertCount, Key.skippedRestAlertCount) }
    }

    /// Extra rest of 5 minutes adds 2 minutes to the next use session.
    var rewardExtraRest: Bool {
        didSet { UserDefaults.standard.set(rewardExtraRest, forKey: Key.rewardExtraRest) }
    }

    var hasPIN: Bool {
        !(UserDefaults.standard.string(forKey: Key.pin) ?? "").isEmpty
    }

    init() {
        let defaults = UserDefaults.standard
        workMinutes = Self.clamp(defaults.object(forKey: Key.workMinutes) as? Int ?? 20, 1...60)
        if let restMinutes = defaults.object(forKey: Key.restMinutes) as? Int {
            self.restMinutes = Self.clamp(restMinutes, 1...60)
        } else if let legacySeconds = defaults.object(forKey: "parent.restSeconds") as? Int {
            self.restMinutes = Self.clamp(max(1, legacySeconds / 60), 1...60)
        } else {
            restMinutes = 10
        }
        dailyLimitMinutes = Self.clamp(defaults.object(forKey: Key.dailyLimitMinutes) as? Int ?? 60, 1...240)
        minimumDistanceCm = Self.clamp(defaults.object(forKey: Key.minimumDistanceCm) as? Int ?? 40, 30...80)
        skippedRestAlertCount = Self.clamp(defaults.object(forKey: Key.skippedRestAlertCount) as? Int ?? 3, 1...10)
        if defaults.object(forKey: Key.requireDistanceCheck) == nil {
            requireDistanceCheck = true
        } else {
            requireDistanceCheck = defaults.bool(forKey: Key.requireDistanceCheck)
        }
        if defaults.object(forKey: Key.rewardExtraRest) == nil {
            rewardExtraRest = true
        } else {
            rewardExtraRest = defaults.bool(forKey: Key.rewardExtraRest)
        }
    }

    func setPIN(_ pin: String) {
        UserDefaults.standard.set(pin, forKey: Key.pin)
    }

    func matchesPIN(_ pin: String) -> Bool {
        UserDefaults.standard.string(forKey: Key.pin) == pin
    }

    private func persist(_ value: Int, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
