import Foundation

/// One repeating daily notification to be scheduled.
struct PlannedReminder: Equatable, Sendable {
    let identifier: String
    let hour: Int
    let minute: Int
    let title: String
    let body: String
}

/// Pure planning logic: which notifications should exist for the given
/// settings and database state. Scheduling side effects live in ReminderScheduler.
enum ReminderPlanner {
    static let identifierPrefix = "worder.reminder."

    /// Times are minutes since midnight; duplicates collapse, order is by time of day.
    static func plan(minutesSinceMidnight: [Int], dueWordCount: Int) -> [PlannedReminder] {
        let body = reminderBody(dueWordCount: dueWordCount)
        return Set(minutesSinceMidnight).sorted().compactMap { minutes in
            guard (0..<24 * 60).contains(minutes) else { return nil }
            return PlannedReminder(
                identifier: "\(identifierPrefix)\(minutes)",
                hour: minutes / 60,
                minute: minutes % 60,
                title: "Worder",
                body: body
            )
        }
    }

    static func reminderBody(dueWordCount: Int) -> String {
        guard dueWordCount > 0 else { return "Время позаниматься английским." }
        return "К повторению: \(dueWordCount) \(russianWordsForm(dueWordCount))."
    }

    private static func russianWordsForm(_ count: Int) -> String {
        let mod100 = count % 100
        if (11...14).contains(mod100) { return "слов" }
        switch count % 10 {
        case 1: return "слово"
        case 2...4: return "слова"
        default: return "слов"
        }
    }
}
