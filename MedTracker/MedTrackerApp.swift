import SwiftUI
import UserNotifications

@main
struct MedTrackerApp: App {
    @State private var model = TrackerModel()
    private let notificationDelegate = NotificationDelegate()

    init() {
        if !AppEnvironment.isUITesting {
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.teal)
        }
    }
}
