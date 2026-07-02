import Foundation
import Observation
import SwiftData
import UserNotifications
import WorderCore

/// Seam over UNUserNotificationCenter so scheduling logic is testable.
protocol UserNotificationCentering: Sendable {
    func requestAuthorization() async throws -> Bool
    func pendingRequestIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func schedule(_ reminder: PlannedReminder) async throws
}

struct SystemNotificationCenter: UserNotificationCentering {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingRequestIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func schedule(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        var components = DateComponents()
        components.hour = reminder.hour
        components.minute = reminder.minute

        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }
}

/// Keeps pending local notifications in sync with reminder settings and the
/// current review backlog. Safe to call often — it replaces its own requests
/// wholesale and never touches notifications scheduled by anyone else.
@MainActor
@Observable
final class ReminderScheduler {
    enum SyncOutcome: Equatable {
        case scheduled(Int)
        case disabled
        case authorizationDenied
        case failed(String)
    }

    private let context: ModelContext
    private let settings: AppSettings
    private let center: any UserNotificationCentering
    private let calendar: Calendar

    private(set) var lastOutcome: SyncOutcome?

    init(
        context: ModelContext,
        settings: AppSettings,
        center: any UserNotificationCentering = SystemNotificationCenter(),
        calendar: Calendar = .current
    ) {
        self.context = context
        self.settings = settings
        self.center = center
        self.calendar = calendar
    }

    func sync(now: Date = .now) async {
        await removeOwnPendingRequests()

        guard settings.remindersEnabled else {
            lastOutcome = .disabled
            return
        }

        do {
            guard try await center.requestAuthorization() else {
                lastOutcome = .authorizationDenied
                return
            }
            let reminders = ReminderPlanner.plan(
                minutesSinceMidnight: settings.reminderTimes,
                dueWordCount: try dueReviewCount(now: now)
            )
            for reminder in reminders {
                try await center.schedule(reminder)
            }
            lastOutcome = .scheduled(reminders.count)
        } catch {
            lastOutcome = .failed(error.localizedDescription)
        }
    }

    private func removeOwnPendingRequests() async {
        let ours = await center.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        if !ours.isEmpty {
            await center.removePendingRequests(withIdentifiers: ours)
        }
    }

    private func dueReviewCount(now: Date) throws -> Int {
        let queue = try SessionQueue(
            context: context,
            configuration: SessionQueue.Configuration(dailyNewWordLimit: settings.dailyNewWordLimit),
            calendar: calendar,
            now: now
        )
        return queue.remainingCount - queue.plannedNewWords.count
    }
}
