import SwiftData
import SwiftUI
import WorderCore

struct WordListView: View {
    @State private var model: WordBrowserViewModel

    init(context: ModelContext) {
        _model = State(initialValue: WordBrowserViewModel(context: context))
    }

    var body: some View {
        List {
            if let message = model.loadFailureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach(model.visibleRows) { row in
                NavigationLink {
                    if let word = model.word(for: row.id) {
                        WordDetailView(word: word)
                    }
                } label: {
                    WordRowView(row: row)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Слова (\(model.totalCount))")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Слово или перевод")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $model.sortOrder) {
                        ForEach(WordSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Сортировка")
            }
        }
        .task { model.refresh() }
    }
}

private struct WordRowView: View {
    let row: WordBrowserViewModel.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.text).bold()
                    if row.isLeech {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(row.translations.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                statusText
                if let errorRate = row.errorRate {
                    Text(errorRate, format: .percent.precision(.fractionLength(0)))
                        .font(.caption)
                        .foregroundStyle(errorRate > 0.3 ? .red : .secondary)
                        .accessibilityLabel("Доля ошибок")
                }
            }
        }
    }

    private var statusText: some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch row.status {
        case .new: "новое"
        case .learning: "изучается"
        case .learned: "выучено"
        }
    }

    private var color: Color {
        switch row.status {
        case .new: .secondary
        case .learning: .orange
        case .learned: .green
        }
    }
}
