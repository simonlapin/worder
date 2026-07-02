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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.dailyNewWordLimitKey) as? Int
        self.dailyNewWordLimit = (stored ?? Self.dailyNewWordLimitDefault)
            .clamped(to: Self.dailyNewWordLimitRange)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
