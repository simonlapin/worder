import Foundation
import SwiftData

/// One recorded answer: what was reviewed, in which direction, and how it was graded.
@Model
public final class ReviewLog {
    public var reviewedAt: Date
    public var directionRaw: String
    public var gradeRaw: String

    public var word: Word?

    public init(reviewedAt: Date, direction: Direction, grade: ReviewGrade) {
        self.reviewedAt = reviewedAt
        self.directionRaw = direction.rawValue
        self.gradeRaw = grade.rawValue
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
