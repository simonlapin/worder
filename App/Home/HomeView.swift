import SwiftData
import SwiftUI
import WorderCore

enum HomeRoute: Hashable {
    case session
    case stats
    case settings
}

struct HomeView: View {
    private let context: ModelContext
    @State private var model: HomeViewModel
    @State private var path: [HomeRoute] = []

    init(context: ModelContext) {
        self.context = context
        _model = State(initialValue: HomeViewModel(context: context))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 32) {
                Spacer()
                counters
                Spacer()
                startButton
            }
            .padding()
            .navigationTitle("Worder")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Статистика", systemImage: "chart.bar") {
                        path.append(.stats)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Настройки", systemImage: "gearshape") {
                        path.append(.settings)
                    }
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .session:
                    SessionView(context: context)
                case .stats:
                    NotBuiltYetView(title: "Статистика")
                case .settings:
                    NotBuiltYetView(title: "Настройки")
                }
            }
            .task { model.refresh() }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { model.refresh() }
            }
        }
    }

    private var counters: some View {
        VStack(spacing: 20) {
            if let message = model.loadFailureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                CounterTile(value: model.dueReviewCount, caption: "к повторению")
                CounterTile(value: model.newWordsTodayCount, caption: "новых сегодня")
                CounterTile(value: model.streakDays, caption: "дней подряд")
            }
        }
    }

    private var startButton: some View {
        Button {
            path.append(.session)
        } label: {
            Text("Заниматься")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.hasWorkAvailable)
    }
}

private struct CounterTile: View {
    let value: Int
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Temporary destination for routes whose screens arrive in later plan steps.
struct NotBuiltYetView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Этот экран ещё не готов."))
            .navigationTitle(title)
    }
}
