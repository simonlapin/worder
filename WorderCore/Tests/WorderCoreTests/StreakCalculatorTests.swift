import Foundation
import SwiftData
import Testing
@testable import WorderCore

struct StreakCalculatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    @Test func noSessionsMeansZeroStreak() {
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: [], now: date(2026, 7, 2))
        #expect(streak == 0)
    }

    @Test func consecutiveDaysEndingTodayAreCounted() {
        let starts = [date(2026, 6, 30), date(2026, 7, 1), date(2026, 7, 2, 9)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2, 20))
        #expect(streak == 3)
    }

    @Test func todayWithoutSessionYetDoesNotBreakTheStreak() {
        let starts = [date(2026, 6, 30), date(2026, 7, 1)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2, 8))
        #expect(streak == 2)
    }

    @Test func missedDayBreaksTheStreak() {
        let starts = [date(2026, 6, 29), date(2026, 6, 30)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2))
        #expect(streak == 0)
    }

    @Test func gapInThePastLimitsTheStreakToItsRecentRun() {
        let starts = [date(2026, 6, 27), date(2026, 6, 28), date(2026, 6, 30), date(2026, 7, 1), date(2026, 7, 2)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2))
        #expect(streak == 3)
    }

    @Test func sessionsAroundMidnightBelongToTheirOwnCalendarDays() {
        let starts = [date(2026, 7, 1, 23, 59), date(2026, 7, 2, 0, 1)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2, 0, 5))
        #expect(streak == 2)
    }

    @Test func multipleSessionsOnOneDayCountOnce() {
        let starts = [date(2026, 7, 2, 9), date(2026, 7, 2, 15), date(2026, 7, 2, 21)]
        let streak = StreakCalculator(calendar: calendar)
            .currentStreak(sessionStartDates: starts, now: date(2026, 7, 2, 22))
        #expect(streak == 1)
    }

    @Test func contextVariantIgnoresUnfinishedSessions() throws {
        let container = try WorderModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let yesterday = date(2026, 7, 1)
        let today = date(2026, 7, 2)
        context.insert(StudySession(startedAt: yesterday, endedAt: yesterday.addingTimeInterval(600)))
        context.insert(StudySession(startedAt: today))
        try context.save()

        let streak = try StreakCalculator(calendar: calendar)
            .currentStreak(in: context, now: date(2026, 7, 2, 20))
        #expect(streak == 1)
    }
}
