import Foundation

struct DailyTime: Codable, Hashable, Comparable, Identifiable {
    let hour: Int
    let minute: Int
    var id: Int { hour * 60 + minute }
    var isValid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.id < rhs.id }
}

enum Weekday: Int, Codable, CaseIterable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

struct Medication: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var dose: String = ""
    var times: [DailyTime]
    var effectiveFrom: Date
    var weekdays: Set<Weekday> = Set(Weekday.allCases)
}

enum DoseOutcome: String, Codable, CaseIterable {
    case taken, skipped, missed
    var title: String { rawValue.capitalized }
}

struct DoseOccurrence: Codable, Identifiable, Equatable {
    let id: String
    let medicationID: UUID
    let medicationName: String
    let dose: String
    let day: String
    let time: DailyTime
    var scheduledAt: Date
    var outcome: DoseOutcome?
    var reportedAt: Date?
}

struct Preferences: Codable, Equatable {
    var hasCompletedOnboarding = false
    var blockingPaused = false
    var notificationsEnabled = true
    var revealMedicationNames = false
}

struct TrackerState: Codable {
    var schemaVersion = 1
    var medications: [Medication] = []
    var occurrences: [DoseOccurrence] = []
    var preferences = Preferences()
    // FamilyActivitySelection is encoded separately to keep the core platform independent.
    var selectionData: Data?
    var previouslyAuthorized = false
    var monitoringFingerprint: String?
    var monitoringTimeZone: String?
    var monitoringError: String?
    var lastReconciledAt: Date
    var lastReconciledDay: String?
    // Optional for compatibility with existing schema-1 stores.
    var practiceSession: PracticeSession?

    init(now: Date = Date()) { lastReconciledAt = now }
}

enum TrackerError: LocalizedError {
    case invalidMedication, tooManyReminders, unavailableContainer, unsupportedSchema
    var errorDescription: String? {
        switch self {
        case .invalidMedication: return "Enter a medication name and at least one valid daily time."
        case .tooManyReminders: return "This version supports up to 60 daily medication reminders."
        case .unavailableContainer: return "The shared App Group is unavailable. Check signing and App Group configuration in all targets."
        case .unsupportedSchema: return "This data was saved by a newer version of MedTracker. Update the app before continuing."
        }
    }
}

extension Medication {
    enum CodingKeys: String, CodingKey {
        case id, name, dose, times, effectiveFrom, weekdays
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dose = try container.decode(String.self, forKey: .dose)
        times = try container.decode([DailyTime].self, forKey: .times)
        effectiveFrom = try container.decode(Date.self, forKey: .effectiveFrom)
        weekdays = try container.decodeIfPresent(Set<Weekday>.self, forKey: .weekdays) ?? Set(Weekday.allCases)
    }
}
