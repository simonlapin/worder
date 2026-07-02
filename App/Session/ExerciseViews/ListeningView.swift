import SwiftUI

struct ListeningView: View {
    let options: [String]
    let onReplay: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 8) {
                Text("Что прозвучало?")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Button(action: onReplay) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 56))
                        .padding(24)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Прослушать ещё раз")
            }
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
