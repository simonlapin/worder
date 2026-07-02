import SwiftData
import SwiftUI
import WorderCore

enum HomeRoute: Hashable {
    case session
    case freeSession
    case stats
    case settings
}

struct HomeView: View {
    private let context: ModelContext
    private let settings: AppSettings
    @State private var model: HomeViewModel
    @State private var path: [HomeRoute] = []
    @State private var ringAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
        _model = State(initialValue: HomeViewModel(context: context, settings: settings))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                Spacer()
                progressRing
                Spacer()
                counters
                startButton
            }
            .padding()
            .background(Color(.systemGroupedBackground))
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
                    SessionView(context: context, settings: settings)
                case .freeSession:
                    SessionView(context: context, settings: settings, mode: .free)
                case .stats:
                    StatsView(context: context)
                case .settings:
                    SettingsView(context: context, settings: settings, store: KeychainStore())
                }
            }
            .task { model.refresh() }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { model.refresh() }
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.brandBlue.opacity(0.12), lineWidth: 18)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    Theme.brandGradient,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text("\(model.learnedWordCount)")
                    .font(Theme.counter(size: 56))
                    .contentTransition(.numericText())
                Text("выучено из \(model.totalWordCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, height: 220)
        .padding(.top, 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.9)) {
                ringAnimated = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Выучено \(model.learnedWordCount) из \(model.totalWordCount) слов")
    }

    private var ringProgress: Double {
        ringAnimated ? max(model.learnedFraction, model.totalWordCount > 0 ? 0.004 : 0) : 0
    }

    private var counters: some View {
        VStack(spacing: 20) {
            if let message = model.loadFailureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                CounterTile(value: model.dueReviewCount, caption: "к повторению", tint: Theme.brandBlue)
                CounterTile(value: model.newWordsTodayCount, caption: "новых сегодня", tint: Theme.brandIndigo)
                CounterTile(
                    value: model.streakDays,
                    caption: "дней подряд",
                    tint: .orange,
                    icon: model.streakDays > 0 ? "flame.fill" : nil
                )
            }
        }
    }

    private var startButton: some View {
        VStack(spacing: 12) {
            Button("Заниматься") {
                path.append(.session)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.hasWorkAvailable)

            Button("Свободная тренировка") {
                path.append(.freeSession)
            }
            .buttonStyle(AnswerButtonStyle())
        }
    }
}

private struct CounterTile: View {
    let value: Int
    let caption: String
    let tint: Color
    var icon: String?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                Text("\(value)")
                    .font(Theme.counter(size: 34))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
