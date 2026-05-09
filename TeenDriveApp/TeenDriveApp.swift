import SwiftUI

@main
struct TeenDriveApp: App {
    @UIApplicationDelegateAdaptor(TeenDriveAppDelegate.self) private var appDelegate

    init() {
        FirebaseBackend.shared.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
