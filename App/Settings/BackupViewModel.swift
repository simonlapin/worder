import Foundation
import Observation
import SwiftData
import WorderCore

@MainActor
@Observable
final class BackupViewModel {
    enum ImportPhase: Equatable {
        case idle
        /// Backup decoded, but the database has data — waiting for the user
        /// to confirm the overwrite.
        case needsConfirmation
        case success(restoredWords: Int)
        case failure(String)
    }

    private let context: ModelContext
    private let settings: AppSettings
    private let exporter = StateExporter()
    private let importer = StateImporter()
    private var pendingBackup: (data: Data, backup: StateBackup)?

    private(set) var importPhase: ImportPhase = .idle
    private(set) var exportFailureMessage: String?

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
    }

    func makeExportData(now: Date = .now) -> Data? {
        do {
            let data = try exporter.export(
                from: context,
                settings: StateBackup.Settings(
                    dailyNewWordLimit: settings.dailyNewWordLimit,
                    remindersEnabled: settings.remindersEnabled,
                    reminderTimes: settings.reminderTimes
                ),
                now: now
            )
            exportFailureMessage = nil
            return data
        } catch {
            exportFailureMessage = error.localizedDescription
            return nil
        }
    }

    func beginImport(data: Data) {
        do {
            let backup = try importer.decode(data)
            if try importer.isDatabaseEmpty(context) {
                try restore(data: data, backup: backup)
            } else {
                pendingBackup = (data, backup)
                importPhase = .needsConfirmation
            }
        } catch {
            pendingBackup = nil
            importPhase = .failure(error.localizedDescription)
        }
    }

    func confirmOverwrite() {
        guard let pending = pendingBackup else { return }
        pendingBackup = nil
        do {
            try importer.eraseAll(in: context)
            try restore(data: pending.data, backup: pending.backup)
        } catch {
            importPhase = .failure(error.localizedDescription)
        }
    }

    func cancelImport() {
        pendingBackup = nil
        importPhase = .idle
    }

    /// Reports a failure that happened before the backup data reached the
    /// model (e.g. the picked file could not be read).
    func reportReadFailure(_ error: any Error) {
        pendingBackup = nil
        importPhase = .failure(error.localizedDescription)
    }

    private func restore(data: Data, backup: StateBackup) throws {
        try importer.importState(data, into: context)
        settings.dailyNewWordLimit = backup.settings.dailyNewWordLimit
        settings.reminderTimes = backup.settings.reminderTimes
        settings.remindersEnabled = backup.settings.remindersEnabled
        let restoredWords = backup.batches.reduce(0) { $0 + $1.words.count } + backup.unbatchedWords.count
        importPhase = .success(restoredWords: restoredWords)
    }
}
