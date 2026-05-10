/*
 File: AccountStore.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Owns local account state, selected role, pairing codes, connected family members, and Firebase profile synchronization.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
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
        let parentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = parentName
        connectedTeenCode = pairing.code

        let connectedTeen = ConnectedTeen(
            name: pairing.teenName.isEmpty ? "Teen \(connectedTeens.count + 1)" : pairing.teenName,
            pairingCode: pairing.code,
            teenProfileID: pairing.teenProfileID,
            familyGroupID: pairing.familyGroupID
        )
        upsert(connectedTeen: connectedTeen)
        await connectParentInFirestore(pairing: pairing, parentName: parentName)
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
     Generates the short numeric code embedded in a teen pairing QR payload.
    */
    private static func makePairingCode() -> String {
        String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
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
    private func syncTeenProfile(userID: String) async {
        guard let db = FirebaseBackend.shared.database else {
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return
        }
        let profileID = teenProfileID.isEmpty ? userID : teenProfileID
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

            teenProfileID = profileID
            familyGroupID = groupID
            await refreshConnectedParentName(teenProfileID: profileID, db: db)
            startTeenProfileListener(teenProfileID: profileID, db: db)
            firebaseStatus = "Teen profile synced"
            markCloudSyncSucceeded()
        } catch {
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
        let profileID = parentProfileID.isEmpty ? userID : parentProfileID
        let name = normalizedDisplayName(fallback: "Parent")
        let familyIDs = Array(Set(connectedTeens.map(\.familyGroupID).filter { !$0.isEmpty }))
        let teenIDs = Array(Set(connectedTeens.map(\.teenProfileID).filter { !$0.isEmpty }))
        let profile = ParentProfile(
            id: profileID,
            displayName: name,
            familyGroupIDs: familyIDs,
            connectedTeenIDs: teenIDs,
            fcmToken: FirebaseBackend.shared.fcmToken,
            updatedAt: Date()
        )

        do {
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
        pairing: (code: String, teenName: String, teenProfileID: String, familyGroupID: String),
        parentName: String
    ) async {
        guard let db = FirebaseBackend.shared.database,
              let userID = await FirebaseBackend.shared.signInIfNeeded(),
              !pairing.teenProfileID.isEmpty,
              !pairing.familyGroupID.isEmpty else {
            firebaseStatus = FirebaseBackend.shared.statusMessage
            cloudSyncState = .blocked(FirebaseBackend.shared.statusMessage)
            return
        }

        parentProfileID = parentProfileID.isEmpty ? userID : parentProfileID
        let familyRef = db.collection("familyGroups").document(pairing.familyGroupID)
        let parentRef = db.collection("parentProfiles").document(parentProfileID)
        let teenRef = db.collection("teenProfiles").document(pairing.teenProfileID)

        do {
            try await familyRef.setData([
                "parentIDs": FieldValue.arrayUnion([parentProfileID]),
                "teenIDs": FieldValue.arrayUnion([pairing.teenProfileID]),
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
        } catch {
            firebaseStatus = "Could not connect teen: \((error as NSError).localizedDescription)"
            cloudSyncState = .failed(firebaseStatus)
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
    private static func pairing(from payload: String) -> (code: String, teenName: String, teenProfileID: String, familyGroupID: String)? {
        if let components = URLComponents(string: payload),
           components.scheme == "teendrive",
           components.host == "pair",
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            let teenName = components.queryItems?.first(where: { $0.name == "teen" })?.value ?? ""
            let teenProfileID = components.queryItems?.first(where: { $0.name == "teenID" })?.value ?? ""
            let familyGroupID = components.queryItems?.first(where: { $0.name == "familyGroupID" })?.value ?? ""
            return (code.uppercased(), teenName, teenProfileID, familyGroupID)
        }

        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : (trimmed.uppercased(), "", "", "")
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
    static let connectedParentName = "account.connectedParentName"
    static let connectedParentID = "account.connectedParentID"
    static let connectedParents = "account.connectedParents"
    static let connectedTeenCode = "account.connectedTeenCode"
    static let connectedTeens = "account.connectedTeens"
    static let familyGroupID = "account.familyGroupID"
    static let teenProfileID = "account.teenProfileID"
    static let parentProfileID = "account.parentProfileID"
    static let lastSuccessfulCloudSyncAt = "account.lastSuccessfulCloudSyncAt"
}
