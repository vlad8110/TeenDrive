/*
 File: AccountStore.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Owns local account state, selected role, pairing codes, connected family members, and Firebase profile synchronization.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import FirebaseAuth
import FirebaseFirestore
import Foundation

// The app runs in one of two modes; role controls which tabs and cloud records are used.
enum AccountRole: String, CaseIterable, Codable, Identifiable {
    case teen
    case parent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teen:
            return "Teen"
        case .parent:
            return "Parent"
        }
    }
}

struct ConnectedTeen: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var pairingCode: String
    var teenProfileID: String
    var familyGroupID: String

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init(
        id: UUID = UUID(),
        name: String,
        pairingCode: String,
        teenProfileID: String = "",
        familyGroupID: String = ""
    ) {
        self.id = id
        self.name = name
        self.pairingCode = pairingCode
        self.teenProfileID = teenProfileID
        self.familyGroupID = familyGroupID
    }
}

struct ConnectedParent: Codable, Hashable, Identifiable {
    let id: String
    var displayName: String
}

private struct PairingPayload {
    let code: String
    let token: String
    let teenName: String
    let teenProfileID: String
    let familyGroupID: String
}

enum AccountCloudSyncState: Equatable {
    case idle
    case syncing
    case upToDate
    case blocked(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .syncing:
            return "Syncing…"
        case .upToDate:
            return "Up to date"
        case .blocked(let message), .failed(let message):
            return message
        }
    }

    var isError: Bool {
        switch self {
        case .blocked, .failed:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var hasSelectedRole: Bool {
        didSet { UserDefaults.standard.set(hasSelectedRole, forKey: Keys.hasSelectedRole) }
    }

    @Published var role: AccountRole {
        didSet { UserDefaults.standard.set(role.rawValue, forKey: Keys.role) }
    }

    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    @Published private(set) var pairingCode: String {
        didSet { UserDefaults.standard.set(pairingCode, forKey: Keys.pairingCode) }
    }

    @Published private(set) var pairingToken: String {
        didSet { UserDefaults.standard.set(pairingToken, forKey: Keys.pairingToken) }
    }

    @Published private(set) var connectedParentName: String {
        didSet { UserDefaults.standard.set(connectedParentName, forKey: Keys.connectedParentName) }
    }

    @Published private(set) var connectedParentID: String {
        didSet { UserDefaults.standard.set(connectedParentID, forKey: Keys.connectedParentID) }
    }

    @Published private(set) var connectedParents: [ConnectedParent] {
        didSet { saveConnectedParents() }
    }

    @Published private(set) var connectedTeenCode: String {
        didSet { UserDefaults.standard.set(connectedTeenCode, forKey: Keys.connectedTeenCode) }
    }

    @Published private(set) var connectedTeens: [ConnectedTeen] {
        didSet { saveConnectedTeens() }
    }

    @Published private(set) var familyGroupID: String {
        didSet { UserDefaults.standard.set(familyGroupID, forKey: Keys.familyGroupID) }
    }

    @Published private(set) var teenProfileID: String {
        didSet { UserDefaults.standard.set(teenProfileID, forKey: Keys.teenProfileID) }
    }

    @Published private(set) var parentProfileID: String {
        didSet { UserDefaults.standard.set(parentProfileID, forKey: Keys.parentProfileID) }
    }

    @Published private(set) var firebaseStatus = "Firebase account not connected"
    @Published private(set) var cloudSyncState: AccountCloudSyncState = .idle
    @Published private(set) var lastSuccessfulCloudSyncAt: Date?
    private var teenProfileListener: ListenerRegistration?

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init() {
        let defaults = UserDefaults.standard
        hasSelectedRole = defaults.object(forKey: Keys.hasSelectedRole) as? Bool ?? false
        let roleValue = defaults.string(forKey: Keys.role) ?? AccountRole.teen.rawValue
        role = AccountRole(rawValue: roleValue) ?? .teen
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        pairingCode = defaults.string(forKey: Keys.pairingCode) ?? AccountStore.makePairingCode()
        pairingToken = defaults.string(forKey: Keys.pairingToken) ?? AccountStore.makePairingToken()
        let storedParentName = defaults.string(forKey: Keys.connectedParentName) ?? ""
        let storedParentID = defaults.string(forKey: Keys.connectedParentID) ?? ""
        connectedParentName = storedParentName
        connectedParentID = storedParentID
        if let data = defaults.data(forKey: Keys.connectedParents),
           let parents = try? JSONDecoder().decode([ConnectedParent].self, from: data) {
            connectedParents = parents
        } else if !storedParentID.isEmpty || !storedParentName.isEmpty {
            connectedParents = [
                ConnectedParent(
                    id: storedParentID.isEmpty ? UUID().uuidString : storedParentID,
                    displayName: storedParentName.isEmpty ? "Parent" : storedParentName
                )
            ]
        } else {
            connectedParents = []
        }
        let storedTeenCode = defaults.string(forKey: Keys.connectedTeenCode) ?? ""
        connectedTeenCode = storedTeenCode
        if let data = defaults.data(forKey: Keys.connectedTeens),
           let teens = try? JSONDecoder().decode([ConnectedTeen].self, from: data) {
            connectedTeens = teens
        } else if !storedTeenCode.isEmpty {
            connectedTeens = [ConnectedTeen(name: "Teen", pairingCode: storedTeenCode)]
        } else {
            connectedTeens = []
        }
        familyGroupID = defaults.string(forKey: Keys.familyGroupID) ?? ""
        teenProfileID = defaults.string(forKey: Keys.teenProfileID) ?? ""
        parentProfileID = defaults.string(forKey: Keys.parentProfileID) ?? ""

        let lastSync = defaults.double(forKey: Keys.lastSuccessfulCloudSyncAt)
        if lastSync > 0 {
            lastSuccessfulCloudSyncAt = Date(timeIntervalSince1970: lastSync)
            cloudSyncState = .upToDate
        }
    }

    /*
     Purpose:
     Cleans up listeners or resources when this object is released.
    */
    deinit {
        teenProfileListener?.remove()
    }

    var isPaired: Bool {
        hasConnectedParent || !connectedTeens.isEmpty
    }

    var hasConnectedParent: Bool {
        !connectedParents.isEmpty || !connectedParentID.isEmpty || !connectedParentName.isEmpty
    }

    var connectedParentDisplayName: String {
        guard hasConnectedParent else { return "" }
        if connectedParents.count > 1 {
            return "\(connectedParents.count) parents connected"
        }
        if let parent = connectedParents.first {
            return parent.displayName
        }
        return connectedParentName.isEmpty ? "Parent" : connectedParentName
    }

    var isPairingReady: Bool {
        !teenProfileID.isEmpty && !familyGroupID.isEmpty
    }

    var pairingPayload: String {
        let teenName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "teendrive"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "code", value: pairingCode),
            URLQueryItem(name: "token", value: pairingToken),
            URLQueryItem(name: "teen", value: teenName),
            URLQueryItem(name: "teenID", value: teenProfileID),
            URLQueryItem(name: "familyGroupID", value: familyGroupID)
        ]
        return components.url?.absoluteString ?? "teendrive://pair?code=\(pairingCode)"
    }

    /*
     Purpose:
     Stores the selected account role and prepares the app to show the matching teen or parent experience.
    */
    func selectRole(_ role: AccountRole) {
        self.role = role
        hasSelectedRole = true
        Task {
            await syncAccount()
        }
    }

    /*
     Purpose:
     Creates a fresh teen pairing code when the current code should no longer be shared.
    */
    func regeneratePairingCode() {
        pairingCode = AccountStore.makePairingCode()
        pairingToken = AccountStore.makePairingToken()
        Task {
            await syncAccount()
        }
    }

    /*
     Purpose:
     Validates a scanned pairing payload and connects the current parent account to the teen.
    */
    func connectParent(name: String, scannedPayload: String) async -> Bool {
        guard let pairing = Self.pairing(from: scannedPayload) else { return false }
        guard !pairing.teenProfileID.isEmpty, !pairing.familyGroupID.isEmpty else {
            firebaseStatus = "Teen QR is not cloud-ready. Open Account on the teen phone while online, then scan the new QR."
            return false
        }
        guard !pairing.token.isEmpty else {
            firebaseStatus = "Teen QR is expired. Generate a new QR code on the teen phone."
            return false
        }
        let parentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = parentName
        connectedTeenCode = pairing.code

        guard await claimPairingToken(pairing: pairing) else { return false }

        let connectedTeen = ConnectedTeen(
            name: pairing.teenName.isEmpty ? "Teen \(connectedTeens.count + 1)" : pairing.teenName,
            pairingCode: pairing.code,
            teenProfileID: pairing.teenProfileID,
            familyGroupID: pairing.familyGroupID
        )
        guard await connectParentInFirestore(pairing: pairing, parentName: parentName) else { return false }
        upsert(connectedTeen: connectedTeen)
        return true
    }

    /*
     Purpose:
     Removes selected teen connections from the parent account list.
    */
    func deleteConnectedTeens(at offsets: IndexSet) {
        connectedTeens.remove(atOffsets: offsets)
        connectedTeenCode = connectedTeens.first?.pairingCode ?? ""
    }

    /*
     Purpose:
     Clears local pairing information and removes listeners so the account can start over safely.
    */
    func disconnect() {
        connectedParentName = ""
        connectedParentID = ""
        connectedParents = []
        connectedTeenCode = ""
        connectedTeens = []
        teenProfileListener?.remove()
        teenProfileListener = nil
        cloudSyncState = lastSuccessfulCloudSyncAt == nil ? .idle : .upToDate
    }

    /*
     Purpose:
     Deletes the current user's cloud account records, removes cloud links to family members, signs out the
     Firebase user, and resets local account settings so the app returns to role selection.

     Teen accounts delete their own trip history, active-drive status, notification events, pairing tokens,
     teen profile, and family teen document. Parent accounts remove their parent ID from connected teen
     records and delete the parent profile without deleting a teen's driving history.
    */
    func deleteAccountAndCloudData() async {
        cloudSyncState = .syncing
        teenProfileListener?.remove()
        teenProfileListener = nil

        if let db = FirebaseBackend.shared.database,
           let userID = await FirebaseBackend.shared.signInIfNeeded() {
            if role == .teen {
                await deleteTeenCloudData(db: db, teenID: teenProfileID.isEmpty ? userID : teenProfileID)
            } else {
                await deleteParentCloudData(db: db, parentID: parentProfileID.isEmpty ? userID : parentProfileID)
            }
            firebaseStatus = "Account data deleted"
        }

        await deleteCurrentFirebaseUser()
        resetLocalAccountState()
    }

    /*
     Purpose:
     Removes cloud data that belongs to a teen account while keeping parent accounts from deleting teen data.
    */
    private func deleteTeenCloudData(db: Firestore, teenID: String) async {
        guard !teenID.isEmpty else { return }
        let groupID = familyGroupID

        if !groupID.isEmpty {
            let teenRef = db.collection("familyGroups").document(groupID).collection("teens").document(teenID)
            await deleteDocuments(in: teenRef.collection("trips"))
            await deleteDocuments(in: teenRef.collection("activeDrive"))
            await deleteDocuments(
                in: db.collection("familyGroups")
                    .document(groupID)
                    .collection("pairingTokens")
                    .whereField("createdByTeenID", isEqualTo: teenID)
            )
            try? await teenRef.delete()
            try? await db.collection("familyGroups").document(groupID).setData([
                "teenIDs": FieldValue.arrayRemove([teenID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        }

        await deleteNotificationEvents(db: db, teenID: teenID)
        try? await db.collection("teenProfiles").document(teenID).delete()
    }

    /*
     Purpose:
     Removes the current parent from cloud relationship records without erasing a teen's trip history.
    */
    private func deleteParentCloudData(db: Firestore, parentID: String) async {
        guard !parentID.isEmpty else { return }

        for teen in connectedTeens {
            guard !teen.familyGroupID.isEmpty, !teen.teenProfileID.isEmpty else { continue }
            let familyRef = db.collection("familyGroups").document(teen.familyGroupID)
            try? await db.collection("teenProfiles").document(teen.teenProfileID).setData([
                "connectedParentIDs": FieldValue.arrayRemove([parentID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            try? await familyRef.collection("teens").document(teen.teenProfileID).setData([
                "connectedParentIDs": FieldValue.arrayRemove([parentID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            try? await familyRef.setData([
                "parentIDs": FieldValue.arrayRemove([parentID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        }

        try? await db.collection("parentProfiles").document(parentID).delete()
    }

    /*
     Purpose:
     Deletes write-only notification event records that belong to the teen account being removed.
    */
    private func deleteNotificationEvents(db: Firestore, teenID: String) async {
        do {
            let snapshot = try await db.collection("notificationEvents")
                .whereField("teenID", isEqualTo: teenID)
                .getDocuments()
            for document in snapshot.documents {
                try? await document.reference.delete()
            }
        } catch {
            firebaseStatus = "Could not delete notification events"
        }
    }

    /*
     Purpose:
     Deletes every document in a small Firestore subcollection used by the app's account cleanup path.
    */
    private func deleteDocuments(in query: Query) async {
        do {
            let snapshot = try await query.getDocuments()
            for document in snapshot.documents {
                try? await document.reference.delete()
            }
        } catch {
            firebaseStatus = "Could not delete cloud records"
        }
    }

    /*
     Purpose:
     Removes the current Firebase Auth user when possible so account deletion also clears authentication state.
    */
    private func deleteCurrentFirebaseUser() async {
        guard FirebaseBackend.shared.isConfigured,
              let user = Auth.auth().currentUser else { return }
        do {
            try await user.delete()
        } catch {
            try? Auth.auth().signOut()
        }
    }

    /*
     Purpose:
     Clears local account defaults and restores the app to its first-run state after data deletion.
    */
    private func resetLocalAccountState() {
        for key in Keys.all {
            UserDefaults.standard.removeObject(forKey: key)
        }

        hasSelectedRole = false
        role = .teen
        displayName = ""
        pairingCode = AccountStore.makePairingCode()
        pairingToken = AccountStore.makePairingToken()
        connectedParentName = ""
        connectedParentID = ""
        connectedParents = []
        connectedTeenCode = ""
        connectedTeens = []
        familyGroupID = ""
        teenProfileID = ""
        parentProfileID = ""
        lastSuccessfulCloudSyncAt = nil
        cloudSyncState = .idle
    }

    /*
     Purpose:
     Generates the short numeric code embedded in a teen pairing QR payload.
    */
    private static func makePairingCode() -> String {
        String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
    }

    /*
     Purpose:
     Generates a hard-to-guess pairing token embedded in the QR code for cloud authorization.
    */
    private static func makePairingToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /*
     Purpose:
     Synchronizes the selected teen or parent account with Firebase while preserving offline local state.
    */
    func syncAccount() async {
        // Keep the local account usable offline, but fill in cloud IDs when Firebase is available.
        guard hasSelectedRole else { return }
        cloudSyncState = .syncing
        guard let userID = await FirebaseBackend.shared.signInIfNeeded() else {
            firebaseStatus = FirebaseBackend.shared.statusMessage
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return
        }

        if role == .teen {
            await syncTeenProfile(userID: userID)
        } else {
            await syncParentProfile(userID: userID)
        }
    }

    /*
     Purpose:
     Creates or updates the teen profile and family group documents in Firestore.
    */
    private func syncTeenProfile(userID: String, allowPermissionRetry: Bool = true) async {
        guard let db = FirebaseBackend.shared.database else {
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return
        }
        if (!teenProfileID.isEmpty && teenProfileID != userID) || (teenProfileID.isEmpty && !familyGroupID.isEmpty) {
            resetTeenCloudLinkForNewFirebaseUser()
        }

        let profileID = userID
        let groupID = familyGroupID.isEmpty ? db.collection("familyGroups").document().documentID : familyGroupID
        let name = normalizedDisplayName(fallback: "Teen")
        let token = FirebaseBackend.shared.fcmToken

        do {
            try await db.collection("familyGroups").document(groupID).setData([
                "teenIDs": FieldValue.arrayUnion([profileID]),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            let profileData: [String: Any] = [
                "familyGroupID": groupID,
                "displayName": name,
                "fcmToken": token as Any,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("teenProfiles").document(profileID).setData(profileData, merge: true)
            try await db.collection("familyGroups").document(groupID).collection("teens").document(profileID).setData(profileData, merge: true)
            try await publishPairingToken(db: db, familyGroupID: groupID, teenProfileID: profileID, teenName: name)

            teenProfileID = profileID
            familyGroupID = groupID
            await refreshConnectedParentName(teenProfileID: profileID, db: db)
            startTeenProfileListener(teenProfileID: profileID, db: db)
            firebaseStatus = "Teen profile synced"
            markCloudSyncSucceeded()
        } catch {
            if allowPermissionRetry, isMissingPermissionError(error) {
                resetTeenCloudLinkForNewFirebaseUser()
                firebaseStatus = "Refreshing teen cloud profile..."
                await syncTeenProfile(userID: userID, allowPermissionRetry: false)
                return
            }
            firebaseStatus = "Could not sync teen profile: \((error as NSError).localizedDescription)"
            cloudSyncState = .failed(firebaseStatus)
        }
    }

    /*
     Purpose:
     Creates or updates the parent profile and refreshes connected teen relationships in Firestore.
    */
    private func syncParentProfile(userID: String) async {
        guard let db = FirebaseBackend.shared.database else {
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return
        }
        if !parentProfileID.isEmpty, parentProfileID != userID {
            resetParentCloudLinkForNewFirebaseUser()
        }

        do {
            let profileID = userID
            let name = normalizedDisplayName(fallback: "Parent")
            let parentRef = db.collection("parentProfiles").document(profileID)
            let savedProfile = try? await parentRef.getDocument()
            let savedFamilyIDs = stringList(from: savedProfile?.data()?["familyGroupIDs"])
            let savedTeenIDs = stringList(from: savedProfile?.data()?["connectedTeenIDs"])
            let localFamilyIDs = connectedTeens.map(\.familyGroupID).filter { !$0.isEmpty }
            let localTeenIDs = connectedTeens.map(\.teenProfileID).filter { !$0.isEmpty }
            let familyIDs = Array(Set(savedFamilyIDs + localFamilyIDs))
            let teenIDs = Array(Set(savedTeenIDs + localTeenIDs))
            let refreshedTeens = await resolveParentConnectedTeens(
                db: db,
                parentID: profileID,
                familyIDs: familyIDs,
                teenIDs: teenIDs
            )

            if !refreshedTeens.isEmpty {
                connectedTeens = refreshedTeens
                connectedTeenCode = refreshedTeens.first?.pairingCode ?? connectedTeenCode
            }

            let resolvedFamilyIDs = connectedTeens.map(\.familyGroupID).filter { !$0.isEmpty }
            let resolvedTeenIDs = connectedTeens.map(\.teenProfileID).filter { !$0.isEmpty }
            let profile = ParentProfile(
                id: profileID,
                displayName: name,
                familyGroupIDs: Array(Set(resolvedFamilyIDs.isEmpty ? familyIDs : resolvedFamilyIDs)),
                connectedTeenIDs: Array(Set(resolvedTeenIDs.isEmpty ? teenIDs : resolvedTeenIDs)),
                fcmToken: FirebaseBackend.shared.fcmToken,
                updatedAt: Date()
            )

            try await db.collection("parentProfiles").document(profileID).setData(profile.firestoreData, merge: true)
            parentProfileID = profileID
            firebaseStatus = "Parent profile synced"
            markCloudSyncSucceeded()
        } catch {
            firebaseStatus = "Could not sync parent profile: \((error as NSError).localizedDescription)"
            cloudSyncState = .failed(firebaseStatus)
        }
    }

    /*
     Purpose:
     Writes the parent-to-teen relationship into the teen profile, parent profile, and family group documents.
    */
    private func connectParentInFirestore(
        pairing: PairingPayload,
        parentName: String
    ) async -> Bool {
        guard let db = FirebaseBackend.shared.database,
              let userID = await FirebaseBackend.shared.signInIfNeeded(),
              !pairing.teenProfileID.isEmpty,
              !pairing.familyGroupID.isEmpty else {
            firebaseStatus = FirebaseBackend.shared.statusMessage
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return false
        }

        if !parentProfileID.isEmpty, parentProfileID != userID {
            resetParentCloudLinkForNewFirebaseUser()
        }
        parentProfileID = userID
        let familyRef = db.collection("familyGroups").document(pairing.familyGroupID)
        let parentRef = db.collection("parentProfiles").document(parentProfileID)
        let teenRef = db.collection("teenProfiles").document(pairing.teenProfileID)

        do {
            try await familyRef.setData([
                "parentIDs": FieldValue.arrayUnion([parentProfileID]),
                "teenIDs": FieldValue.arrayUnion([pairing.teenProfileID]),
                "lastPairingToken": pairing.token,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            try await parentRef.setData([
                "displayName": parentName.isEmpty ? "Parent" : parentName,
                "familyGroupIDs": FieldValue.arrayUnion([pairing.familyGroupID]),
                "connectedTeenIDs": FieldValue.arrayUnion([pairing.teenProfileID]),
                "fcmToken": FirebaseBackend.shared.fcmToken as Any,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            try await teenRef.setData([
                "connectedParentIDs": FieldValue.arrayUnion([parentProfileID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            try await familyRef.collection("teens").document(pairing.teenProfileID).setData([
                "connectedParentIDs": FieldValue.arrayUnion([parentProfileID]),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            firebaseStatus = "Teen connected"
            markCloudSyncSucceeded()
            return true
        } catch {
            firebaseStatus = "Could not connect teen: \((error as NSError).localizedDescription)"
            cloudSyncState = .failed(firebaseStatus)
            return false
        }
    }

    /*
     Purpose:
     Finds the family group that currently links this teen to at least one parent.

     This mirrors the Android sync behavior: trips and live-drive data should be written to the family
     document the parent is actually allowed to read. If the locally stored family ID is stale, this
     method searches the teen profile, parent profiles, and family group records for the newest
     parent-linked family and updates local state before returning it.
    */
    func resolveParentLinkedFamilyGroupID(db: Firestore) async -> String {
        guard role == .teen, !teenProfileID.isEmpty else { return familyGroupID }

        if await familyHasLinkedParent(db: db, familyGroupID: familyGroupID, teenID: teenProfileID) {
            return familyGroupID
        }

        var candidateFamilyIDs: Set<String> = []
        do {
            let teenDocument = try await db.collection("teenProfiles").document(teenProfileID).getDocument()
            let parentIDs = stringList(from: teenDocument.data()?["connectedParentIDs"])
            for parentID in parentIDs {
                let parentDocument = try await db.collection("parentProfiles").document(parentID).getDocument()
                candidateFamilyIDs.formUnion(stringList(from: parentDocument.data()?["familyGroupIDs"]))
            }
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not check parent-linked family"
        }

        if let resolved = await newestParentLinkedFamilyID(db: db, familyIDs: Array(candidateFamilyIDs), teenID: teenProfileID) {
            familyGroupID = resolved
            return resolved
        }

        do {
            let snapshot = try await db.collection("familyGroups")
                .whereField("teenIDs", arrayContains: teenProfileID)
                .getDocuments()
            let familyIDs = snapshot.documents.map(\.documentID)
            if let resolved = await newestParentLinkedFamilyID(db: db, familyIDs: familyIDs, teenID: teenProfileID) {
                familyGroupID = resolved
                return resolved
            }
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not find parent-linked family"
        }

        return familyGroupID
    }

    /*
     Purpose:
     Returns true when a family group contains this teen and at least one parent.
    */
    private func familyHasLinkedParent(db: Firestore, familyGroupID: String, teenID: String) async -> Bool {
        guard !familyGroupID.isEmpty else { return false }
        do {
            let document = try await db.collection("familyGroups").document(familyGroupID).getDocument()
            guard let data = document.data() else { return false }
            return stringList(from: data["teenIDs"]).contains(teenID) && !stringList(from: data["parentIDs"]).isEmpty
        } catch {
            return false
        }
    }

    /*
     Purpose:
     Chooses the newest candidate family group that includes the teen and has a parent linked.
    */
    private func newestParentLinkedFamilyID(db: Firestore, familyIDs: [String], teenID: String) async -> String? {
        var candidates: [(id: String, updatedAt: Date)] = []
        for familyID in Set(familyIDs).filter({ !$0.isEmpty }) {
            do {
                let document = try await db.collection("familyGroups").document(familyID).getDocument()
                guard let data = document.data(),
                      stringList(from: data["teenIDs"]).contains(teenID),
                      !stringList(from: data["parentIDs"]).isEmpty else {
                    continue
                }
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                candidates.append((familyID, updatedAt))
            } catch {
                continue
            }
        }
        return candidates.max { $0.updatedAt < $1.updatedAt }?.id
    }

    /*
     Purpose:
     Rebuilds the parent account's connected teen list from Firestore instead of trusting stale local storage.

     Parent reports are stored under family group paths. If the parent device keeps an old family ID from an
     earlier QR attempt, the reports screen listens to an empty location. This method reads the parent profile,
     verifies each teen still belongs to a family group that contains this parent, and updates local state to
     the newest valid family group before report listeners are attached.
    */
    private func resolveParentConnectedTeens(
        db: Firestore,
        parentID: String,
        familyIDs: [String],
        teenIDs: [String]
    ) async -> [ConnectedTeen] {
        var resolvedTeens: [ConnectedTeen] = []
        let localByTeenID = Dictionary(uniqueKeysWithValues: connectedTeens.compactMap { teen in
            teen.teenProfileID.isEmpty ? nil : (teen.teenProfileID, teen)
        })

        for teenID in Set(teenIDs).filter({ !$0.isEmpty }) {
            let candidateFamilyIDs = await parentFamilyIDs(
                db: db,
                parentID: parentID,
                teenID: teenID,
                knownFamilyIDs: familyIDs
            )
            guard let familyID = await newestParentLinkedFamilyID(
                db: db,
                familyIDs: candidateFamilyIDs,
                teenID: teenID,
                parentID: parentID
            ) else {
                continue
            }

            let teenName = await teenDisplayName(db: db, teenID: teenID)
            let localTeen = localByTeenID[teenID]
            resolvedTeens.append(
                ConnectedTeen(
                    id: localTeen?.id ?? UUID(),
                    name: teenName.isEmpty ? localTeen?.name ?? "Teen" : teenName,
                    pairingCode: localTeen?.pairingCode ?? "",
                    teenProfileID: teenID,
                    familyGroupID: familyID
                )
            )
        }

        return resolvedTeens.sorted { $0.name < $1.name }
    }

    /*
     Purpose:
     Finds family group IDs where the teen and parent are both present.
    */
    private func parentFamilyIDs(db: Firestore, parentID: String, teenID: String, knownFamilyIDs: [String]) async -> [String] {
        var familyIDs = Set(knownFamilyIDs)
        do {
            let snapshot = try await db.collection("familyGroups")
                .whereField("teenIDs", arrayContains: teenID)
                .getDocuments()
            for document in snapshot.documents {
                let parentIDs = stringList(from: document.data()["parentIDs"])
                if parentIDs.contains(parentID) {
                    familyIDs.insert(document.documentID)
                }
            }
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not refresh parent links"
        }
        return Array(familyIDs)
    }

    /*
     Purpose:
     Chooses the newest family group that contains the requested teen and parent.
    */
    private func newestParentLinkedFamilyID(
        db: Firestore,
        familyIDs: [String],
        teenID: String,
        parentID: String
    ) async -> String? {
        var candidates: [(id: String, updatedAt: Date)] = []
        for familyID in Set(familyIDs).filter({ !$0.isEmpty }) {
            do {
                let document = try await db.collection("familyGroups").document(familyID).getDocument()
                guard let data = document.data(),
                      stringList(from: data["teenIDs"]).contains(teenID),
                      stringList(from: data["parentIDs"]).contains(parentID) else {
                    continue
                }
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                candidates.append((familyID, updatedAt))
            } catch {
                continue
            }
        }
        return candidates.max { $0.updatedAt < $1.updatedAt }?.id
    }

    /*
     Purpose:
     Reads the teen's display name so the parent dashboard can label reports after cloud refresh.
    */
    private func teenDisplayName(db: Firestore, teenID: String) async -> String {
        do {
            let document = try await db.collection("teenProfiles").document(teenID).getDocument()
            return (document.data()?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    /*
     Purpose:
     Safely reads Firestore string arrays whose runtime type arrives as Any.
    */
    private func stringList(from value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    /*
     Purpose:
     Publishes a short-lived pairing token so Firestore rules can verify parent linking.
    */
    private func publishPairingToken(db: Firestore, familyGroupID: String, teenProfileID: String, teenName: String) async throws {
        let expiresAt = Date().addingTimeInterval(30 * 60)
        try await db.collection("familyGroups")
            .document(familyGroupID)
            .collection("pairingTokens")
            .document(pairingToken)
            .setData([
                "code": pairingCode,
                "teenID": teenProfileID,
                "teenName": teenName,
                "familyGroupID": familyGroupID,
                "createdByTeenID": teenProfileID,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: expiresAt),
                "usedByParentID": NSNull()
            ], merge: true)
    }

    /*
     Purpose:
     Claims the teen's QR pairing token before writing parent-to-teen relationship records.
    */
    private func claimPairingToken(pairing: PairingPayload) async -> Bool {
        guard let db = FirebaseBackend.shared.database,
              let userID = await FirebaseBackend.shared.signInIfNeeded() else {
            firebaseStatus = FirebaseBackend.shared.statusMessage
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return false
        }

        if !parentProfileID.isEmpty, parentProfileID != userID {
            resetParentCloudLinkForNewFirebaseUser()
        }
        parentProfileID = userID
        let tokenRef = db.collection("familyGroups")
            .document(pairing.familyGroupID)
            .collection("pairingTokens")
            .document(pairing.token)

        do {
            let tokenDocument = try await tokenRef.getDocument()
            guard let data = tokenDocument.data(),
                  data["teenID"] as? String == pairing.teenProfileID,
                  data["familyGroupID"] as? String == pairing.familyGroupID else {
                firebaseStatus = "Teen QR is no longer valid."
                cloudSyncState = .failed(firebaseStatus)
                return false
            }

            if let usedByParentID = data["usedByParentID"] as? String, !usedByParentID.isEmpty, usedByParentID != parentProfileID {
                firebaseStatus = "Teen QR was already used. Generate a new QR code."
                cloudSyncState = .failed(firebaseStatus)
                return false
            }

            guard let expiresAt = data["expiresAt"] as? Timestamp,
                  expiresAt.dateValue() > Date() else {
                firebaseStatus = "Teen QR expired. Generate a new QR code."
                cloudSyncState = .failed(firebaseStatus)
                return false
            }

            try await tokenRef.setData([
                "usedByParentID": parentProfileID,
                "usedAt": FieldValue.serverTimestamp()
            ], merge: true)
            return true
        } catch {
            firebaseStatus = "Could not verify teen QR: \((error as NSError).localizedDescription)"
            cloudSyncState = .failed(firebaseStatus)
            return false
        }
    }

    /*
     Purpose:
     Adds a connected teen or updates the existing matching connection without creating duplicates.
    */
    private func upsert(connectedTeen: ConnectedTeen) {
        connectedTeens.removeAll { existing in
            existing.pairingCode == connectedTeen.pairingCode ||
            (!connectedTeen.teenProfileID.isEmpty && existing.teenProfileID == connectedTeen.teenProfileID)
        }
        connectedTeens.append(connectedTeen)
        connectedTeens.sort { $0.name < $1.name }
    }

    /*
     Purpose:
     Returns a trimmed user display name or a safe fallback when the profile name is empty.
    */
    private func normalizedDisplayName(fallback: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    /*
     Purpose:
     Detects Firestore permission failures so sync can recover from stale local cloud IDs once.
    */
    private func isMissingPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == FirestoreErrorDomain && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    /*
     Purpose:
     Clears stale teen cloud IDs when Firebase Auth creates a new anonymous user.

     Firestore rules require the teen profile document ID to match the signed-in user ID. If an old local
     teenProfileID survives after the auth user changes, profile sync is denied. Resetting the cloud link
     lets the app create a fresh family group and teen profile under the current Firebase user.
    */
    private func resetTeenCloudLinkForNewFirebaseUser() {
        familyGroupID = ""
        teenProfileID = ""
        connectedParentName = ""
        connectedParentID = ""
        connectedParents = []
        pairingCode = AccountStore.makePairingCode()
        pairingToken = AccountStore.makePairingToken()
    }

    /*
     Purpose:
     Clears stale parent cloud IDs when Firebase Auth creates a new anonymous user.
    */
    private func resetParentCloudLinkForNewFirebaseUser() {
        parentProfileID = ""
    }

    /*
     Purpose:
     Records a successful cloud sync timestamp and updates the visible sync state.
    */
    private func markCloudSyncSucceeded() {
        let now = Date()
        lastSuccessfulCloudSyncAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Keys.lastSuccessfulCloudSyncAt)
        cloudSyncState = .upToDate
    }

    /*
     Purpose:
     Loads the connected parent display name for a teen account after pairing or sync.
    */
    private func refreshConnectedParentName(teenProfileID: String, db: Firestore) async {
        do {
            let teenDocument = try await db.collection("teenProfiles").document(teenProfileID).getDocument()
            var parentIDs = teenDocument.data()?["connectedParentIDs"] as? [String] ?? []
            if parentIDs.isEmpty, !familyGroupID.isEmpty {
                let familyDocument = try await db.collection("familyGroups").document(familyGroupID).getDocument()
                parentIDs = familyDocument.data()?["parentIDs"] as? [String] ?? []
            }
            var seenParentIDs: Set<String> = []
            parentIDs = parentIDs.filter { parentID in
                guard !parentID.isEmpty, !seenParentIDs.contains(parentID) else { return false }
                seenParentIDs.insert(parentID)
                return true
            }

            guard !parentIDs.isEmpty else {
                connectedParentName = ""
                connectedParentID = ""
                connectedParents = []
                return
            }

            var parents: [ConnectedParent] = []
            for parentID in parentIDs where !parentID.isEmpty {
                do {
                    let parentDocument = try await db.collection("parentProfiles").document(parentID).getDocument()
                    let parentName = (parentDocument.data()?["displayName"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    parents.append(ConnectedParent(id: parentID, displayName: parentName.isEmpty ? "Parent" : parentName))
                } catch {
                    parents.append(ConnectedParent(id: parentID, displayName: "Parent"))
                }
            }
            parents.sort { $0.displayName < $1.displayName }

            connectedParents = parents
            connectedParentID = parents.first?.id ?? ""
            connectedParentName = parents.first?.displayName ?? ""
        } catch {
            firebaseStatus = "Could not refresh parent status: \((error as NSError).localizedDescription)"
        }
    }

    /*
     Purpose:
     Subscribes to the teen profile so parent connection changes update the teen UI live.
    */
    private func startTeenProfileListener(teenProfileID: String, db: Firestore) {
        teenProfileListener?.remove()
        teenProfileListener = db.collection("teenProfiles")
            .document(teenProfileID)
            .addSnapshotListener { [weak self] _, _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refreshConnectedParentName(teenProfileID: teenProfileID, db: db)
                }
            }
    }

    /*
     Purpose:
     Parses and validates the text stored inside a Teen Drive pairing QR code.
    */
    private static func pairing(from payload: String) -> PairingPayload? {
        if let components = URLComponents(string: payload),
           components.scheme == "teendrive",
           components.host == "pair",
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
            let teenName = components.queryItems?.first(where: { $0.name == "teen" })?.value ?? ""
            let teenProfileID = components.queryItems?.first(where: { $0.name == "teenID" })?.value ?? ""
            let familyGroupID = components.queryItems?.first(where: { $0.name == "familyGroupID" })?.value ?? ""
            return PairingPayload(code: code.uppercased(), token: token, teenName: teenName, teenProfileID: teenProfileID, familyGroupID: familyGroupID)
        }

        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : PairingPayload(code: trimmed.uppercased(), token: "", teenName: "", teenProfileID: "", familyGroupID: "")
    }

    /*
     Purpose:
     Persists the parent account connected-teen list to local storage.
    */
    private func saveConnectedTeens() {
        guard let data = try? JSONEncoder().encode(connectedTeens) else { return }
        UserDefaults.standard.set(data, forKey: Keys.connectedTeens)
    }

    /*
     Purpose:
     Persists the teen account connected-parent list to local storage.
    */
    private func saveConnectedParents() {
        guard let data = try? JSONEncoder().encode(connectedParents) else { return }
        UserDefaults.standard.set(data, forKey: Keys.connectedParents)
    }
}

private enum Keys {
    static let hasSelectedRole = "account.hasSelectedRole"
    static let role = "account.role"
    static let displayName = "account.displayName"
    static let pairingCode = "account.pairingCode"
    static let pairingToken = "account.pairingToken"
    static let connectedParentName = "account.connectedParentName"
    static let connectedParentID = "account.connectedParentID"
    static let connectedParents = "account.connectedParents"
    static let connectedTeenCode = "account.connectedTeenCode"
    static let connectedTeens = "account.connectedTeens"
    static let familyGroupID = "account.familyGroupID"
    static let teenProfileID = "account.teenProfileID"
    static let parentProfileID = "account.parentProfileID"
    static let lastSuccessfulCloudSyncAt = "account.lastSuccessfulCloudSyncAt"

    static let all = [
        hasSelectedRole,
        role,
        displayName,
        pairingCode,
        pairingToken,
        connectedParentName,
        connectedParentID,
        connectedParents,
        connectedTeenCode,
        connectedTeens,
        familyGroupID,
        teenProfileID,
        parentProfileID,
        lastSuccessfulCloudSyncAt
    ]
}
