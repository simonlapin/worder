import SwiftUI
import WorderCore

struct WordDetailView: View {
    let word: Word

    private var recentLogs: [ReviewLog] {
        Array(word.reviewLogs.sorted { $0.reviewedAt > $1.reviewedAt }.prefix(20))
    }

    var body: some View {
        List {
            wordSection
            directionsSection
            if !word.sentences.isEmpty {
                sentencesSection
            }
            if !recentLogs.isEmpty {
                historySection
            }
        }
        .navigationTitle(word.text)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wordSection: some View {
        Section {
            LabeledContent("Переводы", value: word.translations.joined(separator: ", "))
            if let note = word.note {
                LabeledContent("Пометка", value: note)
            }
            if let category = word.category {
                LabeledContent("Категория", value: category)
            }
            if let batch = word.batch {
                LabeledContent("Пачка", value: batch.title)
            }
            LabeledContent("Номер (частотность)", value: "\(word.wordId)")
            if word.isLeech {
                Label("Трудное слово", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let hint = word.leechHint {
                Label(hint, systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var directionsSection: some View {
        Section("Направления") {
            ForEach(Direction.allCases, id: \.self) { direction in
                if let state = word.directionState(for: direction) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(directionTitle(direction)).bold()
                        Text(stateSummary(state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sentencesSection: some View {
        Section("Примеры") {
            ForEach(word.sentences.sorted { $0.createdAt < $1.createdAt }, id: \.persistentModelID) { sentence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence.en)
                    Text(sentence.ru)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var historySection: some View {
        Section("Последние ответы") {
            ForEach(recentLogs, id: \.persistentModelID) { log in
                HStack {
                    Text(log.reviewedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(directionTitle(log.direction))
                        .font(.caption)
                    if log.isFreePractice {
                        Text("тренировка")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    gradeLabel(log.grade)
                }
            }
        }
    }

    private func directionTitle(_ direction: Direction) -> String {
        switch direction {
        case .enToRu: "EN → RU"
        case .ruToEn: "RU → EN"
        }
    }

    private func stateSummary(_ state: DirectionState) -> String {
        var parts: [String] = [stateTitle(state.state)]
        if state.state != .new {
            parts.append("стабильность \(state.stability.formatted(.number.precision(.fractionLength(1)))) дн.")
            parts.append("повторение \(state.due.formatted(.dateTime.day().month().year()))")
            parts.append("ошибок \(state.lapses)")
            parts.append("ответов \(state.reps)")
        }
        return parts.joined(separator: " · ")
    }

    private func stateTitle(_ state: CardState) -> String {
        switch state {
        case .new: "не начато"
        case .learning: "изучается"
        case .review: "в повторениях"
        case .relearning: "переучивается"
        }
    }

    private func gradeLabel(_ grade: ReviewGrade) -> some View {
        let (text, color): (String, Color) = switch grade {
        case .again: ("ошибка", .red)
        case .hard: ("почти", .orange)
        case .good: ("верно", .green)
        case .easy: ("легко", .green)
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(color)
    }
}
