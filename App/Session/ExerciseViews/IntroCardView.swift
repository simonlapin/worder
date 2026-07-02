import SwiftUI

struct IntroCardView: View {
    let card: SessionViewModel.IntroCard
    let onListen: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                EyebrowText(card.leechHint == nil ? "Новое слово" : "Трудное слово")
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(card.text)
                        .font(Theme.headword(size: 46))
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
                if let note = card.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Divider()
                    .frame(width: 64)
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
            }
            .wordCard(tilt: .degrees(-1.2))
            Spacer()
            Button("Понятно", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
    }
}
