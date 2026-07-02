import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionViewModel.Summary
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                    .padding(22)
                    .background(Theme.brandGradient, in: Circle())
                    .symbolEffect(.bounce, value: appeared)
                Text("Сессия завершена")
                    .font(.title2.bold())
                Grid(horizontalSpacing: 24, verticalSpacing: 14) {
                    summaryRow(label: "Слов пройдено", value: "\(summary.wordsStudied)")
                    summaryRow(label: "Точность", value: "\(summary.accuracyPercent)%")
                    summaryRow(label: "Новых слов", value: "\(summary.newWordsIntroduced)")
                    summaryRow(label: "Стрик", value: "\(summary.streakDays) дн.", icon: summary.streakDays > 0 ? "flame.fill" : nil)
                }
            }
            .wordCard()
            Spacer()
            Button("Готово", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .onAppear { appeared = true }
    }

    private func summaryRow(label: String, value: String, icon: String? = nil) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                Text(value)
                    .font(Theme.counter(size: 17))
            }
            .gridColumnAlignment(.trailing)
        }
    }
}
