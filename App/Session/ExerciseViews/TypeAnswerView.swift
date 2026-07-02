import SwiftUI

struct TypeAnswerView: View {
    let exercise: SessionViewModel.Exercise
    let onListen: (() -> Void)?
    let onSubmit: (String) -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ExercisePromptView(exercise: exercise, onListen: onListen)
            TextField("Ответ", text: $input)
                .answerField()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            Spacer()
            Button("Ответить", action: submit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedInput.isEmpty)
        }
        .padding()
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !trimmedInput.isEmpty else { return }
        onSubmit(trimmedInput)
    }
}
