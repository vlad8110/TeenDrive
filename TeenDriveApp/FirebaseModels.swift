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
