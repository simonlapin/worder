import SwiftUI

struct IntroCardView: View {
    let card: SessionViewModel.IntroCard
    let onListen: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(card.leechHint == nil ? "Новое слово" : "Трудное слово")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(card.text)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                if let onListen {
                    Button(action: onListen) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Прослушать")
                }
            }
            if let note = card.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(card.translations.joined(separator: ", "))
                .font(.title2)
                .multilineTextAlignment(.center)
            if let hint = card.leechHint {
                Label {
                    Text(hint)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                }
                .padding(12)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Button {
                onContinue()
            } label: {
                Text("Понятно")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
