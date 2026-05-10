/*
 File: FirebaseBackend.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Configures Firebase, signs users in anonymously, registers for remote notifications, and stores push messaging tokens.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
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

    /*
     Purpose:
     Performs the function operation for this file's feature area.
    */
    private override init() {
        super.init()
    }

    var database: Firestore? {
        guard isConfigured else { return nil }
        return Firestore.firestore()
    }

    /*
     Purpose:
     Initializes Firebase only when the app has a bundled GoogleService-Info configuration file.
    */
    func configureIfPossible() {
        // The app can still run locally without Firebase; cloud features activate when config exists.
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

    /*
     Purpose:
     Returns the current Firebase user ID or signs in anonymously when needed.
    */
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

    /*
     Purpose:
     Prompts the user for permission to show push/local notifications.
    */
    func requestNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            statusMessage = firebaseErrorMessage(prefix: "Notifications permission failed", error: error)
        }
    }

    /*
     Purpose:
     Hands the Apple Push Notification token to Firebase Messaging.
    */
    func setAPNSToken(_ deviceToken: Data) {
        guard isConfigured else { return }
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken
        refreshMessagingTokenIfPossible()
    }

    /*
     Purpose:
     Fetches the Firebase Cloud Messaging token once Firebase and APNs are ready.
    */
    func refreshMessagingTokenIfPossible() {
        guard isConfigured, hasAPNSToken else { return }
        Messaging.messaging().token { [weak self] token, _ in
            Task { @MainActor in
                self?.fcmToken = token
            }
        }
    }

    /*
     Purpose:
     Requests notification permission once per install after cloud sign-in succeeds.
    */
    private func requestNotificationPermissionIfNeeded() {
        guard !hasRequestedNotificationPermission else { return }
        hasRequestedNotificationPermission = true
        UserDefaults.standard.set(true, forKey: Keys.hasRequestedNotificationPermission)
        Task {
            await requestNotificationPermission()
        }
    }

    /*
     Purpose:
     Builds a user-readable status string from a Firebase error.
    */
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
    /*
     Purpose:
     Receives refreshed Firebase Cloud Messaging tokens from the Messaging SDK.
    */
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
        }
    }
}

extension FirebaseBackend: UNUserNotificationCenterDelegate {
    /*
     Purpose:
     Controls how notifications appear when the app is in the foreground.
    */
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

final class TeenDriveAppDelegate: NSObject, UIApplicationDelegate {
    /*
     Purpose:
     Receives the APNs device token from iOS and forwards it to Firebase Messaging.
    */
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            FirebaseBackend.shared.setAPNSToken(deviceToken)
        }
    }

    /*
     Purpose:
     Publishes a phone-unlocked signal when protected data becomes available after device unlock.
    */
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        NotificationCenter.default.post(name: .teenDriveProtectedDataDidBecomeAvailable, object: nil)
    }
}

extension Notification.Name {
    static let teenDriveProtectedDataDidBecomeAvailable = Notification.Name("teenDriveProtectedDataDidBecomeAvailable")
}
