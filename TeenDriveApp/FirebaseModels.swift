import FirebaseFirestore
import Foundation

struct FamilyGroup: Codable, Hashable, Identifiable {
    var id: String
    var parentIDs: [String]
    var teenIDs: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct TeenProfile: Codable, Hashable, Identifiable {
    var id: String
    var familyGroupID: String
    var displayName: String
    var connectedParentIDs: [String]
    var fcmToken: String?
    var updatedAt: Date
}

struct ParentProfile: Codable, Hashable, Identifiable {
    var id: String
    var displayName: String
    var familyGroupIDs: [String]
    var connectedTeenIDs: [String]
    var fcmToken: String?
    var updatedAt: Date
}

struct ActiveTeenDrive: Hashable, Identifiable {
    var id: String { teenProfileID }
    var teenProfileID: String
    var familyGroupID: String
    var teenName: String
    var startedAt: Date
    var updatedAt: Date
    var speedMetersPerSecond: Double
    var topSpeedMetersPerSecond: Double
    var distanceMeters: Double
    var alertCount: Int
    var lastKnownLocation: RoutePoint?
    var safetyAlerts: [SafetyAlert]
    var route: [RoutePoint]

    var speedMPH: Double {
        max(speedMetersPerSecond, 0) * 2.2369362921
    }

    var topSpeedMPH: Double {
        max(topSpeedMetersPerSecond, 0) * 2.2369362921
    }

    var distanceMiles: Double {
        distanceMeters / 1609.344
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}

extension FamilyGroup {
    var firestoreData: [String: Any] {
        [
            "parentIDs": parentIDs,
            "teenIDs": teenIDs,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

extension TeenProfile {
    var firestoreData: [String: Any] {
        [
            "familyGroupID": familyGroupID,
            "displayName": displayName,
            "connectedParentIDs": connectedParentIDs,
            "fcmToken": fcmToken as Any,
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

extension ParentProfile {
    var firestoreData: [String: Any] {
        [
            "displayName": displayName,
            "familyGroupIDs": familyGroupIDs,
            "connectedTeenIDs": connectedTeenIDs,
            "fcmToken": fcmToken as Any,
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}

extension ActiveTeenDrive {
    init?(document: DocumentSnapshot, teen: ConnectedTeen) {
        guard let data = document.data(),
              data["isActive"] as? Bool == true else {
            return nil
        }

        let startedAt = (data["startedAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? startedAt
        let locationData = data["lastKnownLocation"] as? [String: Any]
        let safetyAlertData = data["safetyAlerts"] as? [[String: Any]] ?? []
        let routeData = data["route"] as? [[String: Any]] ?? []

        self.init(
            teenProfileID: teen.teenProfileID,
            familyGroupID: teen.familyGroupID,
            teenName: teen.name,
            startedAt: startedAt,
            updatedAt: updatedAt,
            speedMetersPerSecond: data["speedMetersPerSecond"] as? Double ?? 0,
            topSpeedMetersPerSecond: data["topSpeedMetersPerSecond"] as? Double ?? 0,
            distanceMeters: data["distanceMeters"] as? Double ?? 0,
            alertCount: data["alertCount"] as? Int ?? 0,
            lastKnownLocation: locationData.flatMap(RoutePoint.init(firestoreData:)),
            safetyAlerts: safetyAlertData.compactMap(SafetyAlert.init(firestoreData:)),
            route: routeData.compactMap(RoutePoint.init(firestoreData:))
        )
    }
}
