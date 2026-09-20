import Foundation
import Observation

struct CheckInEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var at: Date
    var succeeded: Bool
    var extraMinutes: Int
    var bonusMinutes: Int
    var skipReason: String?

    var summary: String {
        if !succeeded {
            if let skipReason, !skipReason.isEmpty {
                return "😭 眼睛在受伤 · \(skipReason)"
            }
            return "😭 眼睛在受伤"
        }
        if bonusMinutes > 0 {
            return "😊 爱眼成功 · 多休息 \(extraMinutes) 分 · 下次 +\(bonusMinutes) 分"
        }
        if extraMinutes > 0 {
            return "😊 爱眼成功 · 多休息 \(extraMinutes) 分"
        }
        return "😊 爱眼成功"
    }
}

struct DayRecord: Codable, Identifiable, Equatable {
    var id: String { dayKey }
    var dayKey: String
    var usedSeconds: Int
    var completedRests: Int
    var skippedRests: Int
    var distancePasses: Int
    var alertSent: Bool
    var quotaAlertSent: Bool

    var usedMinutes: Int {
        usedSeconds <= 0 ? 0 : Int((Double(usedSeconds) / 60.0).rounded())
    }

    static func empty(dayKey: String) -> DayRecord {
        DayRecord(
            dayKey: dayKey,
            usedSeconds: 0,
            completedRests: 0,
            skippedRests: 0,
            distancePasses: 0,
            alertSent: false,
            quotaAlertSent: false
        )
    }

    init(
        dayKey: String,
        usedSeconds: Int,
        completedRests: Int,
        skippedRests: Int,
        distancePasses: Int,
        alertSent: Bool,
        quotaAlertSent: Bool
    ) {
        self.dayKey = dayKey
        self.usedSeconds = usedSeconds
        self.completedRests = completedRests
        self.skippedRests = skippedRests
        self.distancePasses = distancePasses
        self.alertSent = alertSent
        self.quotaAlertSent = quotaAlertSent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        usedSeconds = try container.decode(Int.self, forKey: .usedSeconds)
        completedRests = try container.decode(Int.self, forKey: .completedRests)
        skippedRests = try container.decode(Int.self, forKey: .skippedRests)
        distancePasses = try container.decode(Int.self, forKey: .distancePasses)
        alertSent = try container.decodeIfPresent(Bool.self, forKey: .alertSent) ?? false
        quotaAlertSent = try container.decodeIfPresent(Bool.self, forKey: .quotaAlertSent) ?? false
    }
}

@Observable
final class DailyReport {
    private enum Key {
        static let today = "report.today"
        static let history = "report.history"
        static let checkIns = "report.checkIns"
        static let nextBonusMinutes = "report.nextBonusMinutes"
    }

    private(set) var today: DayRecord
    private(set) var history: [DayRecord]
    private(set) var checkIns: [CheckInEvent]
    private(set) var nextBonusMinutes: Int
    private var usageRemainder: TimeInterval = 0

    init() {
        let decoder = JSONDecoder()
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.today),
           let saved = try? decoder.decode(DayRecord.self, from: data) {
            today = saved
        } else {
            today = .empty(dayKey: Self.dayKey(for: Date()))
        }
        if let data = defaults.data(forKey: Key.history),
           let saved = try? decoder.decode([DayRecord].self, from: data) {
            history = saved
        } else {
            history = []
        }
        if let data = defaults.data(forKey: Key.checkIns),
           let saved = try? decoder.decode([CheckInEvent].self, from: data) {
            checkIns = saved
        } else {
            checkIns = []
        }
        nextBonusMinutes = defaults.integer(forKey: Key.nextBonusMinutes)
        rolloverIfNeeded()
    }

    var recentDays: [DayRecord] {
        ([today] + history).prefix(7).map { $0 }
    }

    /// Check-ins that belong to the current local day. Older ones stay stored but stay off today's lists.
    var todaysCheckIns: [CheckInEvent] {
        rolloverIfNeeded()
        let key = today.dayKey
        return checkIns.filter { Self.dayKey(for: $0.at) == key }
    }

    func remainingSeconds(dailyLimitMinutes: Int) -> Int {
        rolloverIfNeeded()
        return max(0, dailyLimitMinutes * 60 - today.usedSeconds)
    }

    func isDailyCapReached(dailyLimitMinutes: Int) -> Bool {
        remainingSeconds(dailyLimitMinutes: dailyLimitMinutes) <= 0
    }

    func addUsage(seconds: TimeInterval) {
        rolloverIfNeeded()
        usageRemainder += max(0, seconds)
        let whole = Int(usageRemainder)
        usageRemainder -= TimeInterval(whole)
        today.usedSeconds += whole
        persist()
    }

    func recordDistancePass() {
        rolloverIfNeeded()
        today.distancePasses += 1
        persist()
    }

    func completeRest() {
        rolloverIfNeeded()
        today.completedRests += 1
        persist()
    }

    func recordCheckIn(succeeded: Bool, extraMinutes: Int, bonusMinutes: Int, skipReason: String? = nil) {
        rolloverIfNeeded()
        let event = CheckInEvent(
            id: UUID(),
            at: Date(),
            succeeded: succeeded,
            extraMinutes: extraMinutes,
            bonusMinutes: bonusMinutes,
            skipReason: skipReason
        )
        checkIns.insert(event, at: 0)
        checkIns = Array(checkIns.prefix(20))
        if bonusMinutes > 0 {
            nextBonusMinutes = min(ExtraRestReward.nextUseMinutes, max(0, bonusMinutes))
        }
        persist()
    }

    func consumeBonus() -> Int {
        let bonus = min(ExtraRestReward.nextUseMinutes, max(0, nextBonusMinutes))
        nextBonusMinutes = 0
        persist()
        return bonus
    }

    func grantBonus(_ minutes: Int) {
        guard minutes > 0 else { return }
        nextBonusMinutes = min(ExtraRestReward.nextUseMinutes, minutes)
        persist()
    }

    @discardableResult
    func skipRest(alertAfter: Int, reason: String) -> Bool {
        rolloverIfNeeded()
        today.skippedRests += 1
        let shouldAlert = today.skippedRests >= alertAfter && !today.alertSent
        if shouldAlert {
            today.alertSent = true
        }
        persist()
        recordCheckIn(succeeded: false, extraMinutes: 0, bonusMinutes: 0, skipReason: reason)
        return shouldAlert
    }

    @discardableResult
    func markQuotaExhausted() -> Bool {
        rolloverIfNeeded()
        guard !today.quotaAlertSent else { return false }
        today.quotaAlertSent = true
        persist()
        return true
    }

    func summaryText(dailyLimitMinutes: Int, alertAfter: Int) -> String {
        rolloverIfNeeded()
        let skippedLine: String
        if today.skippedRests >= alertAfter {
            skippedLine = "未完成休息 \(today.skippedRests) 次，已超过你设的 \(alertAfter) 次提醒。"
        } else {
            skippedLine = "未完成休息 \(today.skippedRests) 次。"
        }
        let failLines = todaysCheckIns.filter { !$0.succeeded }.prefix(8).map(\.summary)
        let failBlock = failLines.isEmpty ? "没有打卡失败记录" : failLines.joined(separator: "\n")
        return """
        EyeHaven 今日报告
        使用 \(today.usedMinutes) / \(dailyLimitMinutes) 分钟
        完成休息 \(today.completedRests) 次
        \(skippedLine)
        测距通过 \(today.distancePasses) 次

        打卡失败：
        \(failBlock)
        """
    }

    private func rolloverIfNeeded() {
        let key = Self.dayKey(for: Date())
        guard today.dayKey != key else { return }
        if today.usedSeconds > 0 || today.completedRests > 0 || today.skippedRests > 0 || today.distancePasses > 0 {
            history.insert(today, at: 0)
            history = Array(history.prefix(14))
        }
        today = .empty(dayKey: key)
        usageRemainder = 0
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(today) {
            UserDefaults.standard.set(data, forKey: Key.today)
        }
        if let data = try? encoder.encode(history) {
            UserDefaults.standard.set(data, forKey: Key.history)
        }
        if let data = try? encoder.encode(checkIns) {
            UserDefaults.standard.set(data, forKey: Key.checkIns)
        }
        UserDefaults.standard.set(nextBonusMinutes, forKey: Key.nextBonusMinutes)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
