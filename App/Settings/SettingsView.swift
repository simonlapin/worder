import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SentenceService.self) private var sentenceService
    @Environment(ReminderScheduler.self) private var reminderScheduler
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

            remindersSection

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

            Section {
                LabeledContent("Статус", value: generationStatusText)
                Button("Сгенерировать сейчас") {
                    Task { await sentenceService.generateMissingSentences() }
                }
                .disabled(!model.hasStoredKey || isGenerating)
            } header: {
                Text("Предложения-примеры")
            } footer: {
                Text("Примеры генерируются пачками для слов в изучении и включают упражнение «контекст».")
            }
        }
        .navigationTitle("Настройки")
        .task { model.refresh() }
        .onChange(of: settings.remindersEnabled) { _, _ in syncReminders() }
        .onChange(of: settings.reminderTimes) { _, _ in syncReminders() }
    }

    private var remindersSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Напоминать о занятиях", isOn: $settings.remindersEnabled)
            if settings.remindersEnabled {
                ForEach(settings.reminderTimes.indices, id: \.self) { index in
                    DatePicker(
                        "Время \(index + 1)",
                        selection: reminderTimeBinding(at: index),
                        displayedComponents: .hourAndMinute
                    )
                }
                .onDelete { settings.reminderTimes.remove(atOffsets: $0) }
                Button("Добавить время", systemImage: "plus") {
                    settings.reminderTimes.append(AppSettings.reminderTimeDefault)
                }
            }
        } header: {
            Text("Напоминания")
        } footer: {
            if reminderScheduler.lastOutcome == .authorizationDenied {
                Text("Уведомления запрещены. Разрешите их для Worder в Настройках iOS.")
                    .foregroundStyle(.red)
            } else if settings.remindersEnabled {
                Text("Ежедневные напоминания с числом слов к повторению.")
            }
        }
    }

    private func reminderTimeBinding(at index: Int) -> Binding<Date> {
        Binding {
            let minutes = settings.reminderTimes.indices.contains(index)
                ? settings.reminderTimes[index]
                : AppSettings.reminderTimeDefault
            return Calendar.current.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        } set: { date in
            guard settings.reminderTimes.indices.contains(index) else { return }
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.reminderTimes[index] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private func syncReminders() {
        Task { await reminderScheduler.sync() }
    }

    private var isGenerating: Bool {
        if case .running = sentenceService.status { return true }
        return false
    }

    private var generationStatusText: String {
        switch sentenceService.status {
        case .idle: "—"
        case .keyMissing: "нужен API-ключ"
        case .running(let done, let total): "генерация \(done + 1) из \(total)…"
        case .finished(let filled): filled > 0 ? "готово, слов заполнено: \(filled)" : "все слова заполнены"
        case .failed(let message): "ошибка: \(message)"
        }
    }
}
