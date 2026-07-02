import SwiftData
import SwiftUI
import WorderCore

@main
struct WorderApp: App {
    private let container: ModelContainer
    @State private var settings = AppSettings()
    @State private var sentenceService: SentenceService

    init() {
        do {
            let container = try WorderModelContainer.make()
            self.container = container
            _sentenceService = State(initialValue: SentenceService(
                context: container.mainContext,
                keyStore: KeychainStore()
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
    }
}

struct RootView: View {
    private enum Phase {
        case importing
        case ready
        case failed(String)
    }

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SentenceService.self) private var sentenceService
    @State private var phase: Phase = .importing

    var body: some View {
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
            Task { await sentenceService.generateMissingSentences() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
