import Foundation

enum DoseEngine {
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func scheduledDate(on day: Date, time: DailyTime, calendar: Calendar) -> Date {
        // Match DeviceActivity's spring-forward policy; take the first repeated hour in autumn.
        calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day,
                      matchingPolicy: .nextTimePreservingSmallerComponents,
                      repeatedTimePolicy: .first, direction: .forward)!
    }

    static func reconcile(_ state: inout TrackerState, now: Date, calendar: Calendar = .current) {
        let today = dayKey(now, calendar: calendar)
        var known = Set(state.occurrences.map(\.id))
        let end = calendar.startOfDay(for: now)
        // Keep the previous logical date across zone changes, rather than reinterpreting
        // its timestamp as yesterday and manufacturing an extra missed dose.
        let parts = state.lastReconciledDay?.split(separator: "-").compactMap { Int($0) }
        let previousDay = parts.flatMap { values -> Date? in
            guard values.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
        } ?? calendar.startOfDay(for: min(state.lastReconciledAt, now))
        var day = min(previousDay, end)
        while day <= end {
            let key = dayKey(day, calendar: calendar)
            for medication in state.medications {
                for time in medication.times {
                    let date = scheduledDate(on: day, time: time, calendar: calendar)
                    guard date >= medication.effectiveFrom else { continue }
                    let id = "\(medication.id.uuidString)|\(key)|\(time.id)"
                    guard known.insert(id).inserted else { continue }
                    state.occurrences.append(DoseOccurrence(
                        id: id, medicationID: medication.id, medicationName: medication.name,
                        dose: medication.dose, day: key, time: time, scheduledAt: date
                    ))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        for index in state.occurrences.indices where state.occurrences[index].outcome == nil {
            if state.occurrences[index].day < today {
                state.occurrences[index].outcome = .missed
                // Missed is inferred, never a self-reported intake.
                state.occurrences[index].reportedAt = nil
            } else if state.occurrences[index].day == today {
                // Wall-clock times follow the current zone, including changes while travelling.
                state.occurrences[index].scheduledAt = scheduledDate(
                    on: now, time: state.occurrences[index].time, calendar: calendar
                )
            }
        }
        state.lastReconciledAt = now
        state.lastReconciledDay = today
    }

    static func today(_ state: TrackerState, now: Date, calendar: Calendar = .current) -> [DoseOccurrence] {
        let key = dayKey(now, calendar: calendar)
        return state.occurrences.filter { $0.day == key }.sorted {
            if $0.scheduledAt != $1.scheduledAt { return $0.scheduledAt < $1.scheduledAt }
            return $0.medicationName.localizedStandardCompare($1.medicationName) == .orderedAscending
        }
    }

    static func due(_ state: TrackerState, now: Date, calendar: Calendar = .current) -> [DoseOccurrence] {
        today(state, now: now, calendar: calendar).filter { $0.outcome == nil && $0.scheduledAt <= now }
    }

    static func upsert(_ medication: Medication, in state: inout TrackerState, now: Date,
                       calendar: Calendar = .current) throws {
        guard !medication.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !medication.times.isEmpty, medication.times.allSatisfy(\.isValid) else {
            throw TrackerError.invalidMedication
        }
        var edited = medication
        edited.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.dose = edited.dose.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.times = Array(Set(edited.times)).sorted()
        let otherCount = state.medications.filter { $0.id != edited.id }.reduce(0) { $0 + $1.times.count }
        guard otherCount + edited.times.count <= 60 else { throw TrackerError.tooManyReminders }
        reconcile(&state, now: now, calendar: calendar)
        edited.effectiveFrom = now
        state.medications.removeAll { $0.id == edited.id }
        state.medications.append(edited)
        // Existing due doses retain their original snapshot; only future pending doses are replaced.
        state.occurrences.removeAll {
            $0.medicationID == edited.id && $0.outcome == nil && $0.scheduledAt > now
        }
        reconcile(&state, now: now, calendar: calendar)
    }

    static func delete(_ id: UUID, from state: inout TrackerState, now: Date,
                       calendar: Calendar = .current) {
        reconcile(&state, now: now, calendar: calendar)
        state.medications.removeAll { $0.id == id }
        // Removing a medication cancels unresolved reminders, without inventing an intake.
        state.occurrences.removeAll { $0.medicationID == id && $0.outcome == nil }
    }

    static func report(_ id: String, outcome: DoseOutcome, in state: inout TrackerState,
                       now: Date, calendar: Calendar = .current) {
        reconcile(&state, now: now, calendar: calendar)
        guard outcome != .missed,
              let index = state.occurrences.firstIndex(where: { $0.id == id }),
              state.occurrences[index].day == dayKey(now, calendar: calendar),
              state.occurrences[index].scheduledAt <= now,
              state.occurrences[index].outcome == nil else { return }
        state.occurrences[index].outcome = outcome
        state.occurrences[index].reportedAt = now
    }
}
