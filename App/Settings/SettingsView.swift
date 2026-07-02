import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SentenceService.self) private var sentenceService
    @Environment(ReminderScheduler.self) private var reminderScheduler
    @State private var model: SettingsViewModel
    @State private var backupModel: BackupViewModel
    @State private var exportDocument: BackupDocument?
    @State private var isImporterPresented = false

    init(context: ModelContext, settings: AppSettings, store: any APIKeyStore) {
        _model = State(initialValue: SettingsViewModel(store: store))
        _backupModel = State(initialValue: BackupViewModel(context: context, settings: settings))
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Новых слов в день", selection: $settings.dailyNewWordLimit) {
                    ForEach(newWordLimitOptions, id: \.self) { option in
                        Text(limitLabel(option)).tag(option)
                    }
                }
            } header: {
                Text("Занятия")
            } footer: {
                if settings.dailyNewWordLimit == nil {
                    Text("Без лимита каждое занятие подмешивает новые слова, пока они не закончатся. Все начатые слова попадают в расписание повторений — объём ежедневных ревью быстро вырастет.")
                }
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

            backupSection
        }
        .navigationTitle("Настройки")
        .task { model.refresh() }
        .onChange(of: settings.remindersEnabled) { _, _ in syncReminders() }
        .onChange(of: settings.reminderTimes) { _, _ in syncReminders() }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { _ in }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "Заменить все данные?",
            isPresented: Binding(
                get: { backupModel.importPhase == .needsConfirmation },
                set: { if !$0, backupModel.importPhase == .needsConfirmation { backupModel.cancelImport() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Заменить", role: .destructive) { backupModel.confirmOverwrite() }
            Button("Отмена", role: .cancel) { backupModel.cancelImport() }
        } message: {
            Text("Текущий прогресс будет безвозвратно удалён и заменён данными из файла.")
        }
    }

    private var backupSection: some View {
        Section {
            Button("Экспортировать данные", systemImage: "square.and.arrow.up") {
                if let data = backupModel.makeExportData() {
                    exportDocument = BackupDocument(data: data)
                }
            }
            Button("Импортировать данные", systemImage: "square.and.arrow.down") {
                isImporterPresented = true
            }
            switch backupModel.importPhase {
            case .success(let restoredWords):
                Label("Восстановлено слов: \(restoredWords)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .idle, .needsConfirmation:
                EmptyView()
            }
            if let message = backupModel.exportFailureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Резервная копия")
        } footer: {
            Text("Файл содержит весь прогресс и настройки, кроме API-ключа.")
        }
    }

    private var exportFilename: String {
        "worder-backup-\(Date.now.formatted(.iso8601.year().month().day())).json"
    }

    private func handleImportSelection(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                backupModel.beginImport(data: try Data(contentsOf: url))
            } catch {
                backupModel.reportReadFailure(error)
            }
        case .failure:
            break
        }
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

    /// Presets plus the current value when it is not one of them (e.g. set
    /// before the presets existed), so the picker always shows a selection.
    private var newWordLimitOptions: [Int?] {
        var options = AppSettings.dailyNewWordLimitPresets
        if let current = settings.dailyNewWordLimit, !options.contains(current) {
            options.append(current)
        }
        return options.sorted { ($0 ?? .max) < ($1 ?? .max) }
    }

    private func limitLabel(_ option: Int?) -> String {
        switch option {
        case nil: "Без лимита"
        case 0: "0 — только повторения"
        case let value?: "\(value)"
        }
    }

    private var isGenerating: Bool {
        if case .running = sentenceService.status { return true }
        return false
    }

    struct BackupDocument: FileDocument {
        static let readableContentTypes: [UTType] = [.json]

        let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration: ReadConfiguration) throws {
            guard let contents = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            data = contents
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
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
