import Foundation
import SwiftData

/// Current streak: consecutive calendar days with at least one finished
/// session, counted back from today — or from yesterday when today has none
/// yet, so a streak is not reported broken before the day is over.
/// A session belongs to the day it started, in the calendar's timezone.
public struct StreakCalculator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func currentStreak(in context: ModelContext, now: Date) throws -> Int {
        let finished = try context.fetch(FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.endedAt != nil }
        ))
        return currentStreak(sessionStartDates: finished.map(\.startedAt), now: now)
    }

    public func currentStreak(sessionStartDates: some Sequence<Date>, now: Date) -> Int {
        let days = Set(sessionStartDates.map { calendar.startOfDay(for: $0) })

        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }

        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
