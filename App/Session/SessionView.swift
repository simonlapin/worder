import SwiftData
import SwiftUI
import WorderCore

struct SessionView: View {
    @State private var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(SentenceService.self) private var sentenceService
    @Environment(LeechHelper.self) private var leechHelper

    private let mode: StudySessionMode
    @State private var transitionToken = 0

    init(context: ModelContext, settings: AppSettings, mode: StudySessionMode = .scheduled) {
        self.mode = mode
        var configuration = SessionViewModel.Configuration()
        configuration.mode = mode
        configuration.queue = SessionQueue.Configuration(dailyNewWordLimit: settings.dailyNewWordLimit)
        _model = State(initialValue: SessionViewModel(context: context, configuration: configuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                ProgressView(value: model.progressFraction)
                    .padding(.horizontal)
            }
            if showsProgress, mode == .free, let status = model.currentWordStatus {
                statusBadge(status)
                    .padding(.top, 8)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(transitionToken)
                .transition(ExerciseTransition.current)
        }
        .animation(.spring(duration: 0.35), value: transitionToken)
        .background(Color(.systemGroupedBackground))
        .onChange(of: model.phase) { _, _ in transitionToken += 1 }
        .navigationTitle(mode == .free ? "Свободная тренировка" : "Сессия")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsProgress {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Завершить") { model.endSession() }
                }
            }
        }
        .task { model.start() }
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == .finished {
                Task {
                    await sentenceService.generateMissingSentences()
                    await leechHelper.fillMissingHints()
                }
            }
        }
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

    private func statusBadge(_ status: WordStatus) -> some View {
        HStack(spacing: 6) {
            Text(statusLabel(status))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(status).opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor(status))
            if model.currentWordIsLeech {
                Label("трудное", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.yellow.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func statusLabel(_ status: WordStatus) -> String {
        switch status {
        case .new: "новое"
        case .learning: "изучается"
        case .learned: "выучено"
        }
    }

    private func statusColor(_ status: WordStatus) -> Color {
        switch status {
        case .new: .secondary
        case .learning: .orange
        case .learned: .green
        }
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
        } else if mode == .free {
            ContentUnavailableView {
                Label("Словарь пуст", systemImage: "checkmark.seal")
            } description: {
                Text("Для свободной тренировки нужны импортированные слова.")
            } actions: {
                Button("Готово") { dismiss() }
            }
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

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(color)
                    .padding(22)
                    .background(color.opacity(0.12), in: Circle())
                    .symbolEffect(.bounce, value: appeared)
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
                                .foregroundStyle(Theme.brandBlue)
                        }
                        .accessibilityLabel("Прослушать")
                    }
                }
                if feedback.willRetry {
                    Text("Слово вернётся в этой сессии")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .wordCard()
            Spacer()
            Button("Дальше", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .onAppear { appeared = true }
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
