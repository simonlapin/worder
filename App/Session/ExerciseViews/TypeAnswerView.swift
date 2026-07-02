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
        VStack(spacing: 20) {
            Spacer()
            ExercisePromptView(exercise: exercise, onListen: onListen)
            TextField("Ответ", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            Spacer()
            Button(action: submit) {
                Text("Ответить")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
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
