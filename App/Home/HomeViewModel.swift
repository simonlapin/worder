import Foundation
import Observation
import SwiftData
import WorderCore

@MainActor
@Observable
final class HomeViewModel {
    private let context: ModelContext
    private let settings: AppSettings
    private let calendar: Calendar

    private(set) var dueReviewCount = 0
    private(set) var newWordsTodayCount = 0
    private(set) var streakDays = 0
    private(set) var learnedWordCount = 0
    private(set) var totalWordCount = 0
    private(set) var loadFailureMessage: String?

    var hasWorkAvailable: Bool { dueReviewCount + newWordsTodayCount > 0 }

    var learnedFraction: Double {
        totalWordCount > 0 ? Double(learnedWordCount) / Double(totalWordCount) : 0
    }

    init(context: ModelContext, settings: AppSettings, calendar: Calendar = .current) {
        self.context = context
        self.settings = settings
        self.calendar = calendar
    }

    func refresh(now: Date = .now) {
        do {
            let queue = try SessionQueue(
                context: context,
                configuration: SessionQueue.Configuration(dailyNewWordLimit: settings.dailyNewWordLimit),
                calendar: calendar,
                now: now
            )
            newWordsTodayCount = queue.plannedNewWords.count
            dueReviewCount = queue.remainingCount - newWordsTodayCount
            streakDays = try StreakCalculator(calendar: calendar).currentStreak(in: context, now: now)
            let totals = try StatsCalculator(
                configuration: .init(sessionHistoryLimit: 0),
                calendar: calendar
            ).snapshot(in: context, now: now).totals
            learnedWordCount = totals.learned
            totalWordCount = totals.total
            loadFailureMessage = nil
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }
}
