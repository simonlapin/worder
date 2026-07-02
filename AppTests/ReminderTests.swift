import Foundation
import SwiftData
import Testing
import WorderCore
@testable import Worder

@Suite struct ReminderPlannerTests {
    @Test func plansSortedDedupedTimesWithStableIdentifiers() {
        let reminders = ReminderPlanner.plan(minutesSinceMidnight: [1200, 540, 1200], dueWordCount: 3)

        #expect(reminders.map(\.identifier) == ["worder.reminder.540", "worder.reminder.1200"])
        #expect(reminders.map(\.hour) == [9, 20])
        #expect(reminders.map(\.minute) == [0, 0])
        #expect(reminders.allSatisfy { $0.body == "К повторению: 3 слова." })
    }

    @Test func outOfRangeTimesAreDropped() {
        let reminders = ReminderPlanner.plan(minutesSinceMidnight: [-10, 540, 24 * 60], dueWordCount: 0)
        #expect(reminders.map(\.identifier) == ["worder.reminder.540"])
    }

    @Test func zeroDueWordsGetGenericText() {
        #expect(ReminderPlanner.reminderBody(dueWordCount: 0) == "Время позаниматься английским.")
    }

    @Test func russianPluralFormsAreCorrect() {
        #expect(ReminderPlanner.reminderBody(dueWordCount: 1) == "К повторению: 1 слово.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 3) == "К повторению: 3 слова.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 5) == "К повторению: 5 слов.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 11) == "К повторению: 11 слов.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 21) == "К повторению: 21 слово.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 104) == "К повторению: 104 слова.")
        #expect(ReminderPlanner.reminderBody(dueWordCount: 112) == "К повторению: 112 слов.")
    }
}

@MainActor
final class MockNotificationCenter: UserNotificationCentering {
    var authorizationGranted = true
    var authorizationError: Error?
    var scheduleError: Error?
    var pending: [String] = []
    private(set) var authorizationRequestCount = 0
    private(set) var removedIdentifiers: [String] = []
    private(set) var scheduled: [PlannedReminder] = []

    nonisolated func requestAuthorization() async throws -> Bool {
        try await MainActor.run {
            authorizationRequestCount += 1
            if let error = authorizationError { throw error }
            return authorizationGranted
        }
    }

    nonisolated func pendingRequestIdentifiers() async -> [String] {
        await MainActor.run { pending }
    }

    nonisolated func removePendingRequests(withIdentifiers identifiers: [String]) async {
        await MainActor.run {
            removedIdentifiers.append(contentsOf: identifiers)
            pending.removeAll { identifiers.contains($0) }
        }
    }

    nonisolated func schedule(_ reminder: PlannedReminder) async throws {
        try await MainActor.run {
            if let error = scheduleError { throw error }
            scheduled.append(reminder)
            pending.append(reminder.identifier)
        }
    }
}

@MainActor
struct ReminderSchedulerTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private let fixtureJSON = Data("""
    {
        "schemaVersion": 1,
        "batchId": "test-batch",
        "title": "Test Batch",
        "words": [
            {"id": 1, "word": "shop", "translations": ["магазин"]},
            {"id": 2, "word": "ring", "translations": ["кольцо", "звонить"]}
        ]
    }
    """.utf8)

    private func makeSettings(enabled: Bool, times: [Int] = [AppSettings.reminderTimeDefault]) -> AppSettings {
        let suiteName = "ReminderSchedulerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.remindersEnabled = enabled
        settings.reminderTimes = times
        return settings
    }

    /// Marks both directions of the first word overdue, giving the queue
    /// exactly two due review items (the "к повторению" count on Home).
    private func makeContext(withDueWord: Bool = false) throws -> ModelContext {
        let context = ModelContext(try WorderModelContainer.make(inMemory: true))
        if withDueWord {
            try BatchImporter(context: context).importBatch(from: fixtureJSON, now: now)
            let words = try context.fetch(FetchDescriptor<Word>(predicate: #Predicate { $0.wordId == 1 }))
            for state in try #require(words.first).directionStates {
                state.state = .review
                state.due = now.addingTimeInterval(-3600)
            }
            try context.save()
        }
        return context
    }

    @Test func disabledRemindersRemoveOwnRequestsAndSkipAuthorization() async throws {
        let center = MockNotificationCenter()
        center.pending = ["worder.reminder.540", "other.notification"]
        let scheduler = ReminderScheduler(
            context: try makeContext(),
            settings: makeSettings(enabled: false),
            center: center
        )

        await scheduler.sync(now: now)

        #expect(scheduler.lastOutcome == .disabled)
        #expect(center.removedIdentifiers == ["worder.reminder.540"])
        #expect(center.pending == ["other.notification"])
        #expect(center.authorizationRequestCount == 0)
        #expect(center.scheduled.isEmpty)
    }

    @Test func enabledRemindersScheduleEachTimeWithDueCountInBody() async throws {
        let center = MockNotificationCenter()
        let scheduler = ReminderScheduler(
            context: try makeContext(withDueWord: true),
            settings: makeSettings(enabled: true, times: [540, 1200]),
            center: center
        )

        await scheduler.sync(now: now)

        #expect(scheduler.lastOutcome == .scheduled(2))
        #expect(center.scheduled.map(\.identifier) == ["worder.reminder.540", "worder.reminder.1200"])
        #expect(center.scheduled.allSatisfy { $0.body == "К повторению: 2 слова." })
    }

    @Test func resyncReplacesPreviouslyScheduledReminders() async throws {
        let center = MockNotificationCenter()
        let settings = makeSettings(enabled: true, times: [540])
        let scheduler = ReminderScheduler(context: try makeContext(), settings: settings, center: center)

        await scheduler.sync(now: now)
        settings.reminderTimes = [600]
        await scheduler.sync(now: now)

        #expect(center.removedIdentifiers == ["worder.reminder.540"])
        #expect(center.pending == ["worder.reminder.600"])
    }

    @Test func deniedAuthorizationSchedulesNothing() async throws {
        let center = MockNotificationCenter()
        center.authorizationGranted = false
        let scheduler = ReminderScheduler(
            context: try makeContext(),
            settings: makeSettings(enabled: true),
            center: center
        )

        await scheduler.sync(now: now)

        #expect(scheduler.lastOutcome == .authorizationDenied)
        #expect(center.scheduled.isEmpty)
    }

    @Test func schedulingErrorSurfacesAsFailedOutcome() async throws {
        let center = MockNotificationCenter()
        center.scheduleError = NSError(domain: "test", code: 1)
        let scheduler = ReminderScheduler(
            context: try makeContext(),
            settings: makeSettings(enabled: true),
            center: center
        )

        await scheduler.sync(now: now)

        guard case .failed = scheduler.lastOutcome else {
            Issue.record("expected .failed, got \(String(describing: scheduler.lastOutcome))")
            return
        }
    }

    @Test func emptyTimesListSchedulesZeroReminders() async throws {
        let center = MockNotificationCenter()
        let scheduler = ReminderScheduler(
            context: try makeContext(),
            settings: makeSettings(enabled: true, times: []),
            center: center
        )

        await scheduler.sync(now: now)

        #expect(scheduler.lastOutcome == .scheduled(0))
        #expect(center.scheduled.isEmpty)
    }
}

@MainActor
struct ReminderSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReminderSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func reminderSettingsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.remindersEnabled)
        #expect(settings.reminderTimes == [AppSettings.reminderTimeDefault])

        settings.remindersEnabled = true
        settings.reminderTimes = [540, 1200]

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.remindersEnabled)
        #expect(reloaded.reminderTimes == [540, 1200])
    }

    @Test func reminderTimesAreClampedToDayRange() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.reminderTimes = [-5, 540, 5000]
        #expect(settings.reminderTimes == [0, 540, 24 * 60 - 1])
    }
}
