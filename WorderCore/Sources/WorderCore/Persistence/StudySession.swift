import Foundation
import SwiftData

/// One study session; the basis for streak and history statistics.
@Model
public final class StudySession {
    public var startedAt: Date
    public var endedAt: Date?
    public var answersTotal: Int
    public var answersCorrect: Int
    public var newWordsIntroduced: Int

    public init(
        startedAt: Date,
        endedAt: Date? = nil,
        answersTotal: Int = 0,
        answersCorrect: Int = 0,
        newWordsIntroduced: Int = 0
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.answersTotal = answersTotal
        self.answersCorrect = answersCorrect
        self.newWordsIntroduced = newWordsIntroduced
    }
}
