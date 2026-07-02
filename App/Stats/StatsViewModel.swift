import Foundation
import Observation
import SwiftData
import WorderCore

@MainActor
@Observable
final class StatsViewModel {
    private let context: ModelContext
    private let calculator: StatsCalculator

    private(set) var snapshot = StatsSnapshot()
    private(set) var loadFailureMessage: String?

    init(context: ModelContext, calculator: StatsCalculator = StatsCalculator()) {
        self.context = context
        self.calculator = calculator
    }

    var learnedFraction: Double {
        snapshot.totals.total > 0 ? Double(snapshot.totals.learned) / Double(snapshot.totals.total) : 0
    }

    func refresh(now: Date = .now) {
        do {
            snapshot = try calculator.snapshot(in: context, now: now)
            loadFailureMessage = nil
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }
}
