import Foundation
import Observation

@Observable
final class ParentSettings {
    private enum Key {
        static let workMinutes = "parent.workMinutes"
        static let restMinutes = "parent.restMinutes"
        static let dailyLimitMinutes = "parent.dailyLimitMinutes" // 旧：总分钟
        static let dailyUseLimit = "parent.dailyUseLimit" // 新：每天可用次数
        static let minimumDistanceCm = "parent.minimumDistanceCm"
        static let requireDistanceCheck = "parent.requireDistanceCheck"
        static let skippedRestAlertCount = "parent.skippedRestAlertCount"
        static let rewardExtraRest = "parent.rewardExtraRest"
        static let rewardBonusMinutes = "parent.rewardBonusMinutes"
        static let restStoriesEnabled = "parent.restStoriesEnabled"
        static let pin = "parent.pin"
    }

    /// Printed at the bottom of parent settings. Unlocks if the 4-digit PIN is forgotten.
    static let masterPIN = "9527"

    var workMinutes: Int {
        didSet { persist(workMinutes, Key.workMinutes) }
    }

    var restMinutes: Int {
        didSet { persist(restMinutes, Key.restMinutes) }
    }

    /// 每天最多可以点「开始使用」的次数。每次开始消耗 1 次。
    var dailyUseLimit: Int {
        didSet { persist(dailyUseLimit, Key.dailyUseLimit) }
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

    /// Extra rest of 10 minutes or more can add bonus minutes to the next use session.
    var rewardExtraRest: Bool {
        didSet { UserDefaults.standard.set(rewardExtraRest, forKey: Key.rewardExtraRest) }
    }

    /// Next-use bonus minutes when reward is on. Parent sets this; hard max 10.
    var rewardBonusMinutes: Int {
        didSet { persist(rewardBonusMinutes, Key.rewardBonusMinutes) }
    }

    /// Show listen controls on the rest page.
    var restStoriesEnabled: Bool {
        didSet { UserDefaults.standard.set(restStoriesEnabled, forKey: Key.restStoriesEnabled) }
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
        if let uses = defaults.object(forKey: Key.dailyUseLimit) as? Int {
            dailyUseLimit = Self.clamp(uses, 1...30)
        } else if let legacyMinutes = defaults.object(forKey: Key.dailyLimitMinutes) as? Int {
            // 旧「每天总分钟」粗略换成次数：按单次使用时长估算
            let work = max(1, defaults.object(forKey: Key.workMinutes) as? Int ?? 20)
            dailyUseLimit = Self.clamp(max(1, legacyMinutes / work), 1...30)
        } else {
            dailyUseLimit = 6
        }
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
        rewardBonusMinutes = Self.clamp(
            defaults.object(forKey: Key.rewardBonusMinutes) as? Int ?? 5,
            1...ExtraRestReward.maxBonusMinutes
        )
        if defaults.object(forKey: Key.restStoriesEnabled) == nil {
            restStoriesEnabled = false
        } else {
            restStoriesEnabled = defaults.bool(forKey: Key.restStoriesEnabled)
        }
    }

    func setPIN(_ pin: String) {
        UserDefaults.standard.set(pin, forKey: Key.pin)
    }

    func matchesPIN(_ pin: String) -> Bool {
        UserDefaults.standard.string(forKey: Key.pin) == pin
    }

    func acceptsUnlock(_ pin: String) -> Bool {
        pin == Self.masterPIN || matchesPIN(pin)
    }

    private func persist(_ value: Int, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
