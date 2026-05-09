import SwiftUI

@main
struct TeenDriveApp: App {
    @UIApplicationDelegateAdaptor(TeenDriveAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
