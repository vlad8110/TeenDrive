/*
 File: TeenDriveNotifications.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Turns safety alerts into local notifications and Firestore notification events for parent push alerts.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import FirebaseFirestore
import Foundation
import UserNotifications

@MainActor
final class TeenDriveNotifications {
    static let shared = TeenDriveNotifications()

    /*
     Purpose:
     Performs the function operation for this file's feature area.
    */
    private init() {}

    /*
     Purpose:
     Processes one safety alert through local notification and optional parent push paths.
    */
    func record(alert: SafetyAlert, accountStore: AccountStore?) async {
        // Every alert is shown locally; teen accounts also write a cloud event for parents.
        await showLocalNotification(for: alert)
        await writeRemoteNotificationEvent(for: alert, accountStore: accountStore)
    }

    /*
     Purpose:
     Displays an immediate local notification for a safety alert.
    */
    private func showLocalNotification(for alert: SafetyAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.kind.title
        content.body = alert.displayText
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "alert-\(alert.id.uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /*
     Purpose:
     Writes a Firestore event that the Cloud Function can fan out to parents.
    */
    private func writeRemoteNotificationEvent(for alert: SafetyAlert, accountStore: AccountStore?) async {
        guard let accountStore,
              accountStore.role == .teen,
              let db = FirebaseBackend.shared.database,
              !accountStore.teenProfileID.isEmpty,
              !accountStore.familyGroupID.isEmpty else { return }

        let data: [String: Any] = [
            "kind": alert.kind.rawValue,
            "title": alert.kind.title,
            "body": alert.displayText,
            "teenID": accountStore.teenProfileID,
            "familyGroupID": accountStore.familyGroupID,
            "timestamp": Timestamp(date: alert.timestamp),
            "speedMetersPerSecond": alert.speedMetersPerSecond as Any,
            "latitude": alert.latitude as Any,
            "longitude": alert.longitude as Any,
            "note": alert.note as Any,
            "createdAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("notificationEvents").document(alert.id.uuidString).setData(data, merge: true)
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not save notification event"
        }
    }
}
