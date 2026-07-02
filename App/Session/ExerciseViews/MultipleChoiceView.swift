import SwiftUI
import WorderCore

struct MultipleChoiceView: View {
    let exercise: SessionViewModel.Exercise
    let options: [String]
    let onListen: (() -> Void)?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ExercisePromptView(exercise: exercise, onListen: onListen)
            Spacer()
            VStack(spacing: 12) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        onSelect(option)
                    }
                    .buttonStyle(AnswerButtonStyle())
                }
            }
        }
        .padding()
    }
}

struct ExercisePromptView: View {
    let exercise: SessionViewModel.Exercise
    let onListen: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            EyebrowText(exercise.direction == .enToRu ? "Как переводится?" : "Какое это слово?")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(exercise.prompt)
                    .font(promptFont)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                if let onListen {
                    Button(action: onListen) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.brandBlue)
                    }
                    .accessibilityLabel("Прослушать")
                }
            }
            if let note = exercise.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .wordCard()
    }

    /// English headwords read like a dictionary entry; Russian prompts stay
    /// in the system sans.
    private var promptFont: Font {
        exercise.direction == .enToRu ? Theme.headword(size: 40) : Theme.counter(size: 34)
    }
}
