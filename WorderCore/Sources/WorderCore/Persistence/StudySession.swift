import Foundation
import SwiftData

/// How a study session was driven.
public enum StudySessionMode: String, Codable, Sendable, CaseIterable {
    /// FSRS-scheduled reviews plus new words up to the daily limit.
    case scheduled
    /// Free practice over the whole dictionary; does not move the schedule.
    case free
}

/// One study session; the basis for streak and history statistics.
@Model
public final class StudySession {
    public var startedAt: Date
    public var endedAt: Date?
    public var answersTotal: Int
    public var answersCorrect: Int
    public var newWordsIntroduced: Int
    public var modeRaw: String = StudySessionMode.scheduled.rawValue

    public init(
        startedAt: Date,
        endedAt: Date? = nil,
        answersTotal: Int = 0,
        answersCorrect: Int = 0,
        newWordsIntroduced: Int = 0,
        mode: StudySessionMode = .scheduled
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.answersTotal = answersTotal
        self.answersCorrect = answersCorrect
        self.newWordsIntroduced = newWordsIntroduced
        self.modeRaw = mode.rawValue
    }

    public var mode: StudySessionMode {
        get { StudySessionMode(rawValue: modeRaw) ?? .scheduled }
        set { modeRaw = newValue.rawValue }
    }
}
