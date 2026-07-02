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
            streakDays = try StreakCalculator(calendar: calendar).currentStreak(in: context, now: now)
            loadFailureMessage = nil
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }
}
