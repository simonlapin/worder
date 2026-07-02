import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model: SettingsViewModel

    init(store: any APIKeyStore) {
        _model = State(initialValue: SettingsViewModel(store: store))
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Stepper(
                    "Новых слов в день: \(settings.dailyNewWordLimit)",
                    value: $settings.dailyNewWordLimit,
                    in: AppSettings.dailyNewWordLimitRange
                )
            } header: {
                Text("Занятия")
            }

            Section {
                if model.hasStoredKey {
                    Label("Ключ сохранён в Keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Удалить ключ", role: .destructive) {
                        model.deleteKey()
                    }
                } else {
                    SecureField("sk-ant-…", text: $model.keyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Сохранить ключ") {
                        model.saveKey()
                    }
                    .disabled(!model.canSaveKey)
                }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Anthropic API")
            } footer: {
                Text("Ключ хранится только в Keychain устройства и включает генерацию предложений-примеров. Без ключа приложение полностью работает офлайн.")
            }
        }
        .navigationTitle("Настройки")
        .task { model.refresh() }
    }
}
