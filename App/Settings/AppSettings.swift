import Foundation
import Observation

/// User-adjustable app settings backed by UserDefaults.
/// The API key is NOT here — it lives in the Keychain only.
@MainActor
@Observable
final class AppSettings {
    static let dailyNewWordLimitKey = "dailyNewWordLimit"
    static let dailyNewWordLimitDefault = 20
    static let dailyNewWordLimitRange = 0...50

    static let remindersEnabledKey = "remindersEnabled"
    static let reminderTimesKey = "reminderTimes"
    /// Minutes since midnight; 20:00 by default.
    static let reminderTimeDefault = 20 * 60
    static let reminderTimeRange = 0...(24 * 60 - 1)

    private let defaults: UserDefaults

    var dailyNewWordLimit: Int {
        didSet {
            let clamped = dailyNewWordLimit.clamped(to: Self.dailyNewWordLimitRange)
            if clamped != dailyNewWordLimit {
                dailyNewWordLimit = clamped
                return
            }
            defaults.set(dailyNewWordLimit, forKey: Self.dailyNewWordLimitKey)
        }
    }

    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Self.remindersEnabledKey) }
    }

    /// Daily reminder times as minutes since midnight, in user-entered order.
    /// Deduplication happens at planning time so in-progress edits keep stable
    /// row identity in the UI.
    var reminderTimes: [Int] {
        didSet {
            let clamped = reminderTimes.map { $0.clamped(to: Self.reminderTimeRange) }
            if clamped != reminderTimes {
                reminderTimes = clamped
                return
            }
            defaults.set(reminderTimes, forKey: Self.reminderTimesKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLimit = defaults.object(forKey: Self.dailyNewWordLimitKey) as? Int
        self.dailyNewWordLimit = (storedLimit ?? Self.dailyNewWordLimitDefault)
            .clamped(to: Self.dailyNewWordLimitRange)
        self.remindersEnabled = defaults.bool(forKey: Self.remindersEnabledKey)
        let storedTimes = defaults.object(forKey: Self.reminderTimesKey) as? [Int]
        self.reminderTimes = (storedTimes ?? [Self.reminderTimeDefault])
            .map { $0.clamped(to: Self.reminderTimeRange) }
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
