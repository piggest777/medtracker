import XCTest
@testable import MedTrackerCore

final class ScreenTimePermissionTests: XCTestCase {
    func testUnresolvedAuthorizationPreservesSavedSelectionAndLastKnownGrant() {
        var state = TrackerState()
        state.previouslyAuthorized = true
        state.selectionData = Data([1, 2, 3])
        state.monitoringFingerprint = "registered"
        ScreenTimePermission.notDetermined.reconcile(&state)
        XCTAssertEqual(state.selectionData, Data([1, 2, 3]))
        XCTAssertTrue(state.previouslyAuthorized)
        XCTAssertEqual(state.monitoringFingerprint, "registered")
    }

    func testUnresolvedAuthorizationDoesNotInventAGrant() {
        var state = TrackerState()
        state.selectionData = Data([1, 2, 3])
        ScreenTimePermission.notDetermined.reconcile(&state)
        XCTAssertFalse(state.previouslyAuthorized)
        XCTAssertEqual(state.selectionData, Data([1, 2, 3]))
    }

    func testConfirmedDenialClearsInvalidTokensAndMonitoring() {
        var state = TrackerState()
        state.previouslyAuthorized = true
        state.selectionData = Data([1, 2, 3])
        state.monitoringFingerprint = "registered"
        ScreenTimePermission.denied.reconcile(&state)
        XCTAssertNil(state.selectionData)
        XCTAssertNil(state.monitoringFingerprint)
        XCTAssertFalse(state.previouslyAuthorized)
    }

    func testApprovalKeepsSelection() {
        var state = TrackerState()
        state.selectionData = Data([1, 2, 3])
        ScreenTimePermission.approved.reconcile(&state)
        XCTAssertEqual(state.selectionData, Data([1, 2, 3]))
        XCTAssertTrue(state.previouslyAuthorized)
    }
}
