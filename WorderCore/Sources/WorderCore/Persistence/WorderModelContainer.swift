import Foundation
import SwiftData

/// Factory for the app's `ModelContainer`; tests use the in-memory variant.
public enum WorderModelContainer {
    public static var schema: Schema {
        Schema([
            Batch.self,
            Word.self,
            DirectionState.self,
            ReviewLog.self,
            CachedSentence.self,
            StudySession.self,
        ])
    }

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
