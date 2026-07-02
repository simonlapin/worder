import Foundation
import SwiftData
import WorderCore

enum AppBootstrap {
    static let bundledBatchResource = "core-1500"

    enum BootstrapError: LocalizedError {
        case missingBundledBatch(resource: String)

        var errorDescription: String? {
            switch self {
            case .missingBundledBatch(let resource):
                "Bundled word batch \"\(resource).json\" is missing from the app bundle."
            }
        }
    }

    /// Imports the bundled word batch. Safe to run on every launch:
    /// `BatchImporter` is idempotent and never touches learning state.
    @discardableResult
    static func importBundledBatch(
        into context: ModelContext,
        from bundle: Bundle = .main,
        now: Date
    ) throws -> BatchImportSummary {
        guard let url = bundle.url(forResource: bundledBatchResource, withExtension: "json") else {
            throw BootstrapError.missingBundledBatch(resource: bundledBatchResource)
        }
        let data = try Data(contentsOf: url)
        return try BatchImporter(context: context).importBatch(from: data, now: now)
    }
}
