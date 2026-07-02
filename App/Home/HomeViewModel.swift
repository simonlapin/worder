import Foundation
import Observation
import SwiftData
import WorderCore

@MainActor
@Observable
final class HomeViewModel {
    private let context: ModelContext
    private let calendar: Calendar

    private(set) var dueReviewCount = 0
    private(set) var newWordsTodayCount = 0
    private(set) var streakDays = 0
    private(set) var loadFailureMessage: String?

    var hasWorkAvailable: Bool { dueReviewCount + newWordsTodayCount > 0 }

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func refresh(now: Date = .now) {
        do {
            let queue = try SessionQueue(context: context, calendar: calendar, now: now)
            newWordsTodayCount = queue.plannedNewWords.count
            dueReviewCount = queue.remainingCount - newWordsTodayCount
            streakDays = try currentStreak(now: now)
            loadFailureMessage = nil
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }

    /// Consecutive calendar days with at least one finished session, counted
    /// back from today (or yesterday, if today has none yet). A session
    /// belongs to the day it started.
    private func currentStreak(now: Date) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.endedAt != nil }
        ))
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })

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
