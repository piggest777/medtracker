import SwiftUI
import UserNotifications

@main
struct MedTrackerApp: App {
    @StateObject private var model = TrackerModel()
    private let notificationDelegate = NotificationDelegate()

    init() {
        if !AppEnvironment.isUITesting {
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.teal)
        }
    }
}
