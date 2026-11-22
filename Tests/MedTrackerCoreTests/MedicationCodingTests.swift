//
//  MedicationCodingTests.swift
//  MedTrackerCore
//
//  Created by Denis Rakitin on 2026-11-22.
//
import Foundation
import Testing
@testable import MedTrackerCore

private let legacyJSON = """
{
    "id": "00000000-0000-0000-0000-000000000001",
    "name": "Example",
    "dose": "One tablet",
    "times": [{"hour": 8, "minute": 0}],
    "effectiveFrom": 0
}
"""


struct MedicationCodingTests {
    @Test
    func missingDefaultsToEveryDay() throws {
        let data = legacyJSON.data(using: .utf8)!

        let medication = try JSONDecoder().decode(Medication.self, from: data)

        #expect(medication.weekdays == Set(Weekday.allCases))
    }

    @Test
    func selectedWeekdaysSurviveRoundTrip() throws {
        let original: Medication = .init(
                id: .init(),
                name: "Example",
                dose: "One tablet",
                times: [.init(hour: 8, minute: 0)],
                effectiveFrom: Date(timeIntervalSinceReferenceDate: 0),
                weekdays: .init([.monday, .wednesday, .friday])
            )

        let data = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(Medication.self, from: data)

        #expect(decoded.self == original)
    }

    @Test(arguments: [0, 8])
    func invalidWeekdayIsRejected(value: Int) throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(legacyJSON.utf8)
        )

        var json = try #require(object as? [String: Any])

        // Add the invalid value to the JSON being tested.
        json["weekdays"] = [value]

        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Medication.self, from: data)
        }
    }

}
