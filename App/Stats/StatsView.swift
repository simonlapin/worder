import SwiftData
import SwiftUI
import WorderCore

struct StatsView: View {
    @State private var model: StatsViewModel

    init(context: ModelContext) {
        _model = State(initialValue: StatsViewModel(context: context))
    }

    var body: some View {
        List {
            if let message = model.loadFailureMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            overviewSection
            if model.snapshot.batches.count > 1 {
                breakdownSection(title: "По пачкам", groups: model.snapshot.batches)
            }
            if !model.snapshot.categories.isEmpty {
                breakdownSection(title: "По категориям", groups: model.snapshot.categories)
            }
            if !model.snapshot.leeches.isEmpty {
                leechSection
            }
            if !model.snapshot.recentSessions.isEmpty {
                sessionSection
            }
        }
        .navigationTitle("Статистика")
        .task { model.refresh() }
    }

    private var overviewSection: some View {
        Section("Прогресс") {
            HStack(spacing: 12) {
                StatusTile(value: model.snapshot.totals.new, caption: "новые", tint: .secondary)
                StatusTile(value: model.snapshot.totals.learning, caption: "изучаются", tint: .orange)
                StatusTile(value: model.snapshot.totals.learned, caption: "выучены", tint: .green)
            }
            .listRowSeparator(.hidden)
            ProgressView(value: model.learnedFraction) {
                Text("Выучено \(model.snapshot.totals.learned) из \(model.snapshot.totals.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tint(.green)
            LabeledContent("Стрик") {
                Text("\(model.snapshot.streakDays) дн.")
            }
        }
    }

    private func breakdownSection(title: String, groups: [StatsSnapshot.GroupBreakdown]) -> some View {
        Section(title) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                    Text("новые \(group.counts.new) · изучаются \(group.counts.learning) · выучены \(group.counts.learned)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var leechSection: some View {
        Section("Трудные слова") {
            ForEach(model.snapshot.leeches, id: \.text) { leech in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(leech.text).bold()
                        Text(leech.translations.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    if let hint = leech.hint {
                        Label(hint, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sessionSection: some View {
        Section {
            ForEach(model.snapshot.recentSessions, id: \.startedAt) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.startedAt, format: .dateTime.day().month().year())
                        Text("ответов: \(session.answersTotal) · новых слов: \(session.newWordsIntroduced)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let accuracy = session.accuracy {
                        Text(accuracy, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(accuracy >= 0.8 ? .green : .orange)
                    }
                }
            }
        } header: {
            Text("Сессии")
        } footer: {
            if model.snapshot.finishedSessionCount > model.snapshot.recentSessions.count {
                Text("Показаны последние \(model.snapshot.recentSessions.count) из \(model.snapshot.finishedSessionCount).")
            }
        }
    }
}

private struct StatusTile: View {
    let value: Int
    let caption: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
