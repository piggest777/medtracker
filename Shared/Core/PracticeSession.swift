import Foundation

struct PracticeDose: Codable, Identifiable, Equatable {
    var id = UUID()
    let title: String
    let day: Int
    var outcome: DoseOutcome?
}

/// Persisted separately from medication occurrences. It never advances the real clock.
struct PracticeSession: Codable, Equatable {
    var day = 1
    private(set) var doses: [PracticeDose] = []

    init() { makeDosesDue() }

    var currentDoses: [PracticeDose] { Array(doses.filter { $0.day == day }.suffix(2)) }
    var pendingCount: Int { currentDoses.filter { $0.outcome == nil }.count }
    var history: [PracticeDose] { Array(doses.filter { $0.outcome != nil }.reversed()) }

    mutating func makeDosesDue() {
        guard pendingCount == 0 else { return }
        doses.append(contentsOf: [
            PracticeDose(title: "Practice dose 1", day: day),
            PracticeDose(title: "Practice dose 2", day: day)
        ])
    }

    mutating func record(_ id: UUID, outcome: DoseOutcome) {
        guard outcome != .missed,
              let index = doses.firstIndex(where: { $0.id == id && $0.day == day && $0.outcome == nil }) else { return }
        doses[index].outcome = outcome
    }

    mutating func advanceDay() {
        for index in doses.indices where doses[index].day == day && doses[index].outcome == nil {
            doses[index].outcome = .missed
        }
        day += 1
        // The new practice day starts before its next dose, demonstrating the midnight reset.
        // "Make doses due now" triggers that day's doses without waiting.
    }
}

enum BlockingDemand {
    static func dueCount(_ state: TrackerState, now: Date, calendar: Calendar = .current) -> Int {
        if let practice = state.practiceSession { return practice.pendingCount }
        return DoseEngine.due(state, now: now, calendar: calendar).count
    }
}
