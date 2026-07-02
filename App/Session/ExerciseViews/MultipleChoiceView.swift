import SwiftUI

struct MultipleChoiceView: View {
    let exercise: SessionViewModel.Exercise
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ExercisePromptView(exercise: exercise)
            Spacer()
            VStack(spacing: 12) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option)
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }
}

struct ExercisePromptView: View {
    let exercise: SessionViewModel.Exercise

    var body: some View {
        VStack(spacing: 8) {
            Text(exercise.direction == .enToRu ? "Как переводится?" : "Какое это слово?")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(exercise.prompt)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if let note = exercise.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
