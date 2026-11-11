import Foundation

enum ScreenTimePermission: String {
    case notDetermined, denied, approved

    func reconcile(_ state: inout TrackerState) {
        switch self {
        case .approved:
            state.previouslyAuthorized = true
        case .denied:
            state.previouslyAuthorized = false
            state.selectionData = nil
            state.monitoringFingerprint = nil
        case .notDetermined:
            // AuthorizationCenter starts here in each process. Preserve the last known
            // grant and saved selection until an authoritative status arrives.
            break
        }
    }
}
