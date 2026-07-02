import Foundation
import Observation
import SwiftData
import WorderCore

enum WordSortOrder: String, CaseIterable, Identifiable {
    case alphabetical
    case status
    case errorRate
    case nextReview
    case frequency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: "По алфавиту"
        case .status: "По статусу"
        case .errorRate: "По ошибкам"
        case .nextReview: "По повторению"
        case .frequency: "По частотности"
        }
    }
}

@MainActor
@Observable
final class WordBrowserViewModel {
    struct Row: Identifiable, Equatable {
        let id: PersistentIdentifier
        let wordId: Int
        let text: String
        let translations: [String]
        let status: WordStatus
        let isLeech: Bool
        let answersTotal: Int
        let answersWrong: Int
        /// Earliest scheduled review among started directions; nil for new words.
        let nextDue: Date?

        var errorRate: Double? {
            answersTotal > 0 ? Double(answersWrong) / Double(answersTotal) : nil
        }
    }

    private let context: ModelContext
    private let masteryPolicy: MasteryPolicy
    private var rows: [Row] = []
    private var wordsById: [PersistentIdentifier: Word] = [:]

    var sortOrder: WordSortOrder = .alphabetical
    var searchText = ""
    private(set) var loadFailureMessage: String?

    init(context: ModelContext, masteryPolicy: MasteryPolicy = MasteryPolicy()) {
        self.context = context
        self.masteryPolicy = masteryPolicy
    }

    func refresh(now: Date = .now) {
        do {
            let words = try context.fetch(FetchDescriptor<Word>())
            wordsById = Dictionary(uniqueKeysWithValues: words.map { ($0.persistentModelID, $0) })
            rows = words.map { word in
                let logs = word.reviewLogs
                let started = word.directionStates.filter { $0.state != .new }
                return Row(
                    id: word.persistentModelID,
                    wordId: word.wordId,
                    text: word.text,
                    translations: word.translations,
                    status: masteryPolicy.status(of: word, now: now),
                    isLeech: word.isLeech,
                    answersTotal: logs.count,
                    answersWrong: logs.count { $0.grade == .again },
                    nextDue: started.map(\.due).min()
                )
            }
            loadFailureMessage = nil
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }

    var visibleRows: [Row] {
        sorted(filtered(rows))
    }

    var totalCount: Int { rows.count }

    func word(for id: PersistentIdentifier) -> Word? {
        wordsById[id]
    }

    private func filtered(_ rows: [Row]) -> [Row] {
        let query = TranslationIndex.normalize(searchText)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            TranslationIndex.normalize(row.text).contains(query)
                || row.translations.contains { TranslationIndex.normalize($0).contains(query) }
        }
    }

    private func sorted(_ rows: [Row]) -> [Row] {
        switch sortOrder {
        case .alphabetical:
            rows.sorted { ($0.text, $0.wordId) < ($1.text, $1.wordId) }
        case .status:
            // Words in progress first, mastered next, untouched tail.
            rows.sorted {
                (statusRank($0.status), $0.text, $0.wordId)
                    < (statusRank($1.status), $1.text, $1.wordId)
            }
        case .errorRate:
            // Most problematic first; unanswered words at the end.
            rows.sorted {
                (($0.errorRate ?? -1), Double($0.answersTotal), $1.text)
                    > (($1.errorRate ?? -1), Double($1.answersTotal), $0.text)
            }
        case .nextReview:
            rows.sorted {
                ($0.nextDue ?? .distantFuture, $0.text, $0.wordId)
                    < ($1.nextDue ?? .distantFuture, $1.text, $1.wordId)
            }
        case .frequency:
            rows.sorted { $0.wordId < $1.wordId }
        }
    }

    private func statusRank(_ status: WordStatus) -> Int {
        switch status {
        case .learning: 0
        case .learned: 1
        case .new: 2
        }
    }
}
