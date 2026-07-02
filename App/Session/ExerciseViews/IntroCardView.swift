import SwiftUI

struct IntroCardView: View {
    let card: SessionViewModel.IntroCard
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Новое слово")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(card.text)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if let note = card.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(card.translations.joined(separator: ", "))
                .font(.title2)
                .multilineTextAlignment(.center)
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
