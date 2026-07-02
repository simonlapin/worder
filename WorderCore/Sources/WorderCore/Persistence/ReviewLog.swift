import Foundation
import SwiftData

/// One recorded answer: what was reviewed, in which direction, and how it was graded.
@Model
public final class ReviewLog {
    public var reviewedAt: Date
    public var directionRaw: String
    public var gradeRaw: String
    /// True for answers given in free practice mode: they never move the
    /// FSRS schedule and do not consume the daily new-word budget.
    public var isFreePractice: Bool = false

    public var word: Word?

    public init(reviewedAt: Date, direction: Direction, grade: ReviewGrade, isFreePractice: Bool = false) {
        self.reviewedAt = reviewedAt
        self.directionRaw = direction.rawValue
        self.gradeRaw = grade.rawValue
        self.isFreePractice = isFreePractice
    }

    public var direction: Direction {
        get { Direction(rawValue: directionRaw) ?? .enToRu }
        set { directionRaw = newValue.rawValue }
    }

    public var grade: ReviewGrade {
        get { ReviewGrade(rawValue: gradeRaw) ?? .again }
        set { gradeRaw = newValue.rawValue }
    }
}
