import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

@MainActor
final class FirebaseBackend: NSObject, ObservableObject {
    static let shared = FirebaseBackend()

    @Published private(set) var isConfigured = false
    @Published private(set) var authUserID: String?
    @Published private(set) var fcmToken: String?
    @Published var statusMessage = "Firebase not configured"
    private var hasRequestedNotificationPermission = UserDefaults.standard.bool(forKey: Keys.hasRequestedNotificationPermission)
    private var hasAPNSToken = false

    private override init() {
        super.init()
    }

    var database: Firestore? {
        guard isConfigured else { return nil }
        return Firestore.firestore()
    }

    func configureIfPossible() {
        guard !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            statusMessage = "Add GoogleService-Info.plist to enable Firebase"
            return
        }

        FirebaseApp.configure()
        isConfigured = true
        statusMessage = "Firebase configured"
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    func signInIfNeeded() async -> String? {
        configureIfPossible()
        guard isConfigured else { return nil }

        if let user = Auth.auth().currentUser {
            authUserID = user.uid
            requestNotificationPermissionIfNeeded()
            refreshMessagingTokenIfPossible()
            return user.uid
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            authUserID = result.user.uid
            requestNotificationPermissionIfNeeded()
            refreshMessagingTokenIfPossible()
            return result.user.uid
        } catch {
            statusMessage = firebaseErrorMessage(prefix: "Firebase sign-in failed", error: error)
            return nil
        }
    }

    func requestNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            statusMessage = firebaseErrorMessage(prefix: "Notifications permission failed", error: error)
        }
    }

    func setAPNSToken(_ deviceToken: Data) {
        guard isConfigured else { return }
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken
        refreshMessagingTokenIfPossible()
    }

    func refreshMessagingTokenIfPossible() {
        guard isConfigured, hasAPNSToken else { return }
        Messaging.messaging().token { [weak self] token, _ in
            Task { @MainActor in
                self?.fcmToken = token
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard !hasRequestedNotificationPermission else { return }
        hasRequestedNotificationPermission = true
        UserDefaults.standard.set(true, forKey: Keys.hasRequestedNotificationPermission)
        Task {
            await requestNotificationPermission()
        }
    }

    private func firebaseErrorMessage(prefix: String, error: Error) -> String {
        let nsError = error as NSError
        if let message = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            return "\(prefix): \(message)"
        }
        return "\(prefix): \(nsError.localizedDescription)"
    }
}

private enum Keys {
    static let hasRequestedNotificationPermission = "firebase.hasRequestedNotificationPermission"
}

extension FirebaseBackend: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
        }
    }
}

extension FirebaseBackend: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

final class TeenDriveAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            FirebaseBackend.shared.setAPNSToken(deviceToken)
        }
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        NotificationCenter.default.post(name: .teenDriveProtectedDataDidBecomeAvailable, object: nil)
    }
}

extension Notification.Name {
    static let teenDriveProtectedDataDidBecomeAvailable = Notification.Name("teenDriveProtectedDataDidBecomeAvailable")
}
