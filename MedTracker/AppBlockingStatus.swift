import FamilyControls
import ManagedSettings

/// A readback of this app's named Screen Time store, not restrictions from other apps.
struct AppliedShields {
    var applications: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []
    var websites: Set<WebDomainToken> = []

    static func read(selection: FamilyActivitySelection) -> AppliedShields {
        let shield = ManagedSettingsStore(named: BlockingRuntime.storeName).shield
        let appCategories = categories(in: shield.applicationCategories, selection: selection.categoryTokens)
        let webCategories = categories(in: shield.webDomainCategories, selection: selection.categoryTokens)
        return AppliedShields(applications: shield.applications ?? [],
                              categories: appCategories.intersection(webCategories),
                              websites: shield.webDomains ?? [])
    }

    func covers(_ selection: FamilyActivitySelection) -> Bool {
        applications.isSuperset(of: selection.applicationTokens)
            && categories.isSuperset(of: selection.categoryTokens)
            && websites.isSuperset(of: selection.webDomainTokens)
    }

    private static func categories<Activity>(in policy: ShieldSettings.ActivityCategoryPolicy<Activity>?,
                                             selection: Set<ActivityCategoryToken>) -> Set<ActivityCategoryToken> {
        switch policy {
        case .specific(let tokens, let exceptions) where exceptions.isEmpty: return tokens
        case .all(let exceptions) where exceptions.isEmpty: return selection
        default: return []
        }
    }
}

enum AppBlockingStatus {
    case blocked, available, paused, needsAccess, notScheduled, notBlocked, unavailable, preview

    var title: String {
        switch self {
        case .blocked: return "Blocked"
        case .available: return "Available"
        case .paused: return "Paused"
        case .needsAccess: return "Access needed"
        case .notScheduled: return "No schedule"
        case .notBlocked: return "Not blocked"
        case .unavailable: return "Unavailable"
        case .preview: return "Preview"
        }
    }

    var icon: String {
        switch self {
        case .blocked: return "lock.fill"
        case .available: return "lock.open"
        case .paused: return "pause.circle"
        case .needsAccess, .notBlocked, .unavailable: return "exclamationmark.circle"
        case .notScheduled: return "calendar"
        case .preview: return "iphone"
        }
    }
}
