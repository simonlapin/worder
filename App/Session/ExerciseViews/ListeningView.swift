import SwiftUI

struct ListeningView: View {
    let options: [String]
    let onReplay: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 20) {
                EyebrowText("Что прозвучало?")
                Button(action: onReplay) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .padding(32)
                        .background(Theme.brandGradient, in: Circle())
                }
                .accessibilityLabel("Прослушать ещё раз")
            }
            .wordCard()
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
