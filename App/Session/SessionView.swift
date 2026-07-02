import SwiftData
import SwiftUI
import WorderCore

struct SessionView: View {
    @State private var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(context: ModelContext) {
        _model = State(initialValue: SessionViewModel(context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                ProgressView(value: model.progressFraction)
                    .padding(.horizontal)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Сессия")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsProgress {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Завершить") { model.endSession() }
                }
            }
        }
        .task { model.start() }
    }

    private var showsProgress: Bool {
        switch model.phase {
        case .introduction, .exercise, .feedback: true
        case .loading, .finished, .failed: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .introduction(let card):
            IntroCardView(card: card, onListen: listenAction) { model.completeIntroduction() }
        case .exercise(let exercise):
            exerciseView(exercise)
        case .feedback(let feedback):
            FeedbackView(feedback: feedback, onListen: listenAction) { model.continueAfterFeedback() }
        case .finished:
            finishedView
        case .failed(let message):
            ContentUnavailableView {
                Label("Сессия прервана", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("К главному экрану") { dismiss() }
            }
        }
    }

    private var listenAction: (() -> Void)? {
        model.canSpeakCurrentWord ? { model.speakCurrentWord() } : nil
    }

    @ViewBuilder
    private func exerciseView(_ exercise: SessionViewModel.Exercise) -> some View {
        switch exercise.input {
        case .multipleChoice(let options):
            MultipleChoiceView(exercise: exercise, options: options, onListen: listenAction) { option in
                model.submitChoice(option)
            }
        case .typedAnswer:
            TypeAnswerView(exercise: exercise, onListen: listenAction) { input in
                model.submitTypedAnswer(input)
            }
        case .listening(let options):
            ListeningView(options: options) {
                model.speakCurrentWord()
            } onSelect: { option in
                model.submitChoice(option)
            }
        case .context(let translation):
            ContextView(exercise: exercise, translation: translation) { input in
                model.submitTypedAnswer(input)
            }
        }
    }

    @ViewBuilder
    private var finishedView: some View {
        if let summary = model.summary {
            SessionSummaryView(summary: summary) { dismiss() }
        } else {
            ContentUnavailableView {
                Label("Сейчас нечего повторять", systemImage: "checkmark.seal")
            } description: {
                Text("Все слова повторены, новые появятся по расписанию.")
            } actions: {
                Button("Готово") { dismiss() }
            }
        }
    }
}

private struct FeedbackView: View {
    let feedback: SessionViewModel.Feedback
    let onListen: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(color)
            Text(title)
                .font(.title2.bold())
            HStack(spacing: 12) {
                Text(detail)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if let onListen {
                    Button(action: onListen) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Прослушать")
                }
            }
            if feedback.willRetry {
                Text("Слово вернётся в этой сессии")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onContinue()
            } label: {
                Text("Дальше")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var icon: String {
        switch feedback.verdict {
        case .correct, .correctSynonym: "checkmark.circle.fill"
        case .almostCorrect: "checkmark.circle.badge.questionmark"
        case .wrong: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch feedback.verdict {
        case .correct, .correctSynonym: .green
        case .almostCorrect: .orange
        case .wrong: .red
        }
    }

    private var title: String {
        switch feedback.verdict {
        case .correct: "Верно!"
        case .correctSynonym: "Верно, это синоним"
        case .almostCorrect: "Почти — опечатка"
        case .wrong: "Неверно"
        }
    }

    private var detail: String {
        switch feedback.verdict {
        case .correct:
            feedback.correctAnswer
        case .correctSynonym(let intended):
            "Спрашивалось слово «\(intended)»"
        case .almostCorrect, .wrong:
            "Правильный ответ: \(feedback.correctAnswer)"
        }
    }
}
