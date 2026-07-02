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
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                EyebrowText("Заполните пропуск")
                Text(exercise.prompt)
                    .font(Theme.headword(size: 26))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Divider()
                    .frame(width: 64)
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .wordCard()
            TextField("Слово", text: $input)
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
