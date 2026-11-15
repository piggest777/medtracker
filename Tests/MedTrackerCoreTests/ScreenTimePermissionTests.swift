import Foundation
@testable import MedTrackerCore
import Testing


struct ScreenTimePermissionTests {
    @Test("Unresolved authorization preserves saved state", arguments: [true, false])
    func unresolvedAuthorizationPreservesSavedState(previouslyAuthorized: Bool) {
        let savedSelection = Data([1, 2, 3])
        let savedFingerprint: String? = previouslyAuthorized ? "registered" : nil

        var state = TrackerState()
        state.previouslyAuthorized = previouslyAuthorized
        state.selectionData = savedSelection
        state.monitoringFingerprint = savedFingerprint

        ScreenTimePermission.notDetermined.reconcile(&state)

        #expect(state.previouslyAuthorized == previouslyAuthorized)
        #expect(state.selectionData == savedSelection)
        #expect(state.monitoringFingerprint == savedFingerprint)
    }

    @Test
    func testConfirmedDenialClearsInvalidTokensAndMonitoring() {
        var state = TrackerState()
        state.previouslyAuthorized = true
        state.selectionData = Data([1, 2, 3])
        state.monitoringFingerprint = "registered"
        ScreenTimePermission.denied.reconcile(&state)
        #expect(state.selectionData == nil)
        #expect(state.monitoringFingerprint == nil)
        #expect(!state.previouslyAuthorized)
    }

    @Test
    func testApprovalKeepsSelection() {
        var state = TrackerState()
        state.selectionData = Data([1, 2, 3])
        ScreenTimePermission.approved.reconcile(&state)
        #expect(state.selectionData == Data([1, 2, 3]))
        #expect(state.previouslyAuthorized)
    }
}
