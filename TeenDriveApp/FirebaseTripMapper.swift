/*
 File: FirebaseTripMapper.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Converts local route, alert, and trip models to and from Firestore dictionaries.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import FirebaseFirestore
import Foundation

extension RoutePoint {
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": Timestamp(date: timestamp)
        ]
    }

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init?(firestoreData data: [String: Any]) {
        guard let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else { return nil }

        id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        self.latitude = latitude
        self.longitude = longitude
        timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
    }
}

extension SpeedAlert {
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "timestamp": Timestamp(date: timestamp),
            "speedMetersPerSecond": speedMetersPerSecond,
            "latitude": latitude,
            "longitude": longitude
        ]
    }

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init?(firestoreData data: [String: Any]) {
        guard let speedMetersPerSecond = data["speedMetersPerSecond"] as? Double,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else { return nil }

        id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        self.speedMetersPerSecond = speedMetersPerSecond
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension SafetyAlert {
    var firestoreData: [String: Any] {
        [
            "id": id.uuidString,
            "kind": kind.rawValue,
            "timestamp": Timestamp(date: timestamp),
            "speedMetersPerSecond": speedMetersPerSecond as Any,
            "latitude": latitude as Any,
            "longitude": longitude as Any,
            "note": note as Any
        ]
    }

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init?(firestoreData data: [String: Any]) {
        guard let kindValue = data["kind"] as? String,
              let kind = SafetyAlertKind(rawValue: kindValue) else { return nil }

        id = UUID(uuidString: data["id"] as? String ?? "") ?? UUID()
        self.kind = kind
        timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        speedMetersPerSecond = data["speedMetersPerSecond"] as? Double
        latitude = data["latitude"] as? Double
        longitude = data["longitude"] as? Double
        note = data["note"] as? String
    }
}

extension TeenTrip {
    /*
     Purpose:
     Builds a Firestore dictionary representation of this model.
    */
    func firestoreData(teenID: String, familyGroupID: String) -> [String: Any] {
        [
            "id": id.uuidString,
            "teenID": teenID,
            "familyGroupID": familyGroupID,
            "startedAt": Timestamp(date: startedAt),
            "endedAt": Timestamp(date: endedAt),
            "distanceMeters": distanceMeters,
            "durationSeconds": duration,
            "topSpeedMetersPerSecond": topSpeedMetersPerSecond,
            "topSpeedMPH": topSpeedMPH,
            "speedAlerts": speedAlerts.map(\.firestoreData),
            "safetyAlerts": safetyAlerts.map(\.firestoreData),
            "route": route.map(\.firestoreData),
            "syncedAt": FieldValue.serverTimestamp()
        ]
    }

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init?(document: QueryDocumentSnapshot) {
        self.init(firestoreID: document.documentID, data: document.data())
    }

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init?(firestoreID: String, data: [String: Any]) {
        guard let startedAt = (data["startedAt"] as? Timestamp)?.dateValue(),
              let endedAt = (data["endedAt"] as? Timestamp)?.dateValue(),
              let distanceMeters = data["distanceMeters"] as? Double,
              let topSpeedMetersPerSecond = data["topSpeedMetersPerSecond"] as? Double else { return nil }

        let speedAlertData = data["speedAlerts"] as? [[String: Any]] ?? []
        let safetyAlertData = data["safetyAlerts"] as? [[String: Any]] ?? []
        let routeData = data["route"] as? [[String: Any]] ?? []

        self.init(
            id: UUID(uuidString: data["id"] as? String ?? firestoreID) ?? UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            speedAlerts: speedAlertData.compactMap(SpeedAlert.init(firestoreData:)),
            safetyAlerts: safetyAlertData.compactMap(SafetyAlert.init(firestoreData:)),
            route: routeData.compactMap(RoutePoint.init(firestoreData:))
        )
    }
}
