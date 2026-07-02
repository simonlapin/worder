import SwiftData
import SwiftUI
import WorderCore

@main
struct WorderApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var sentenceService: SentenceService
    @State private var leechHelper: LeechHelper
    @State private var reminderScheduler: ReminderScheduler

    init() {
        do {
            let container = try WorderModelContainer.make()
            self.container = container
            let settings = AppSettings()
            _settings = State(initialValue: settings)
            _sentenceService = State(initialValue: SentenceService(
                context: container.mainContext,
                keyStore: KeychainStore()
            ))
            _leechHelper = State(initialValue: LeechHelper(
                context: container.mainContext,
                keyStore: KeychainStore()
            ))
            _reminderScheduler = State(initialValue: ReminderScheduler(
                context: container.mainContext,
                settings: settings
            ))
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .environment(settings)
        .environment(sentenceService)
        .environment(leechHelper)
        .environment(reminderScheduler)
    }
}

struct RootView: View {
    private enum Phase {
        case importing
        case ready
        case failed(String)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(SentenceService.self) private var sentenceService
    @Environment(LeechHelper.self) private var leechHelper
    @Environment(ReminderScheduler.self) private var reminderScheduler
    @State private var phase: Phase = .importing

    var body: some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                // Refresh pending notifications with the current backlog count
                // every time the app leaves the foreground.
                if newPhase == .background {
                    Task { await reminderScheduler.sync() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .importing:
            ProgressView("Подготовка словаря…")
                .task { runBootstrap() }
        case .ready:
            HomeView(context: context, settings: settings)
        case .failed(let message):
            ContentUnavailableView {
                Label("Словарь не загрузился", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Повторить") {
                    phase = .importing
                }
            }
        }
    }

    private func runBootstrap() {
        do {
            try AppBootstrap.importBundledBatch(into: context, now: .now)
            phase = .ready
            Task {
                await reminderScheduler.sync()
                await sentenceService.generateMissingSentences()
                await leechHelper.fillMissingHints()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
