import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionViewModel.Summary
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Сессия завершена")
                .font(.title2.bold())
            Grid(horizontalSpacing: 24, verticalSpacing: 12) {
                summaryRow(label: "Слов пройдено", value: "\(summary.wordsStudied)")
                summaryRow(label: "Точность", value: "\(summary.accuracyPercent)%")
                summaryRow(label: "Новых слов", value: "\(summary.newWordsIntroduced)")
                summaryRow(label: "Стрик", value: "\(summary.streakDays) дн.")
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            Button {
                onDone()
            } label: {
                Text("Готово")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func summaryRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.headline)
                .gridColumnAlignment(.trailing)
        }
    }
}
