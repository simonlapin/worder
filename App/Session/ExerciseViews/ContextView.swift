import SwiftUI

struct ContextView: View {
    let exercise: SessionViewModel.Exercise
    let translation: String
    let onSubmit: (String) -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 12) {
                Text("Заполните пропуск")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(exercise.prompt)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("Слово", text: $input)
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
