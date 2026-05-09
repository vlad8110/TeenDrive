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
            await requestNotificationPermission()
            refreshMessagingToken()
            return user.uid
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            authUserID = result.user.uid
            await requestNotificationPermission()
            refreshMessagingToken()
            return result.user.uid
        } catch {
            statusMessage = "Firebase sign-in failed"
            return nil
        }
    }

    func requestNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            statusMessage = "Notifications permission failed"
        }
    }

    func refreshMessagingToken() {
        guard isConfigured else { return }
        Messaging.messaging().token { [weak self] token, _ in
            Task { @MainActor in
                self?.fcmToken = token
            }
        }
    }
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
        Messaging.messaging().apnsToken = deviceToken
    }
}
