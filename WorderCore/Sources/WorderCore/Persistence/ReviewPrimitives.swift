import Foundation

/// Translation direction of an exercise. Each word tracks FSRS state per direction.
public enum Direction: String, Codable, Sendable, CaseIterable {
    case enToRu
    case ruToEn
}

/// FSRS card lifecycle state.
public enum CardState: String, Codable, Sendable, CaseIterable {
    case new
    case learning
    case review
    case relearning
}

/// Review rating fed into the scheduler.
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    case again
    case hard
    case good
    case easy
}
