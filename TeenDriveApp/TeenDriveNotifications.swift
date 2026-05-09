import FirebaseFirestore
import Foundation
import UserNotifications

@MainActor
final class TeenDriveNotifications {
    static let shared = TeenDriveNotifications()

    private init() {}

    func record(alert: SafetyAlert, accountStore: AccountStore?) async {
        await showLocalNotification(for: alert)
        await writeRemoteNotificationEvent(for: alert, accountStore: accountStore)
    }

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
