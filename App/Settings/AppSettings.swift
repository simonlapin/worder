import Foundation
import Observation

/// User-adjustable app settings backed by UserDefaults.
/// The API key is NOT here — it lives in the Keychain only.
@MainActor
@Observable
final class AppSettings {
    static let dailyNewWordLimitKey = "dailyNewWordLimit"
    static let dailyNewWordLimitDefault = 20
    /// Sentinel stored in UserDefaults for "no limit" (nil in the API).
    static let dailyNewWordLimitUnlimitedSentinel = -1
    static let dailyNewWordLimitPresets: [Int?] = [0, 5, 10, 20, 30, 50, 100, 200, 500, nil]

    static let remindersEnabledKey = "remindersEnabled"
    static let reminderTimesKey = "reminderTimes"
    /// Minutes since midnight; 20:00 by default.
    static let reminderTimeDefault = 20 * 60
    static let reminderTimeRange = 0...(24 * 60 - 1)

    private let defaults: UserDefaults

    /// Maximum new words introduced per day; nil = no limit.
    var dailyNewWordLimit: Int? {
        didSet {
            if let limit = dailyNewWordLimit, limit < 0 {
                dailyNewWordLimit = 0
                return
            }
            defaults.set(
                dailyNewWordLimit ?? Self.dailyNewWordLimitUnlimitedSentinel,
                forKey: Self.dailyNewWordLimitKey
            )
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
        switch defaults.object(forKey: Self.dailyNewWordLimitKey) as? Int {
        case Self.dailyNewWordLimitUnlimitedSentinel:
            self.dailyNewWordLimit = nil
        case let stored?:
            self.dailyNewWordLimit = max(0, stored)
        case nil:
            self.dailyNewWordLimit = Self.dailyNewWordLimitDefault
        }
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
