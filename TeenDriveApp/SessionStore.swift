/*
 File: SessionStore.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Loads, saves, merges, syncs, and listens for local trips, remote trip summaries, and active teen drives.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import FirebaseFirestore
import Foundation

struct ParentTripSummary: Identifiable, Hashable {
    var id: String { "\(teenProfileID)-\(trip.id.uuidString)" }
    let teenProfileID: String
    let familyGroupID: String
    let teenName: String
    let trip: TeenTrip
}

@MainActor
final class SessionStore: ObservableObject {
    private static let deletedSessionIDsKey = "teenDrive.deletedSessionIDs"

    @Published private(set) var sessions: [TeenTrip] = []
    @Published private(set) var parentTripSummaries: [ParentTripSummary] = []
    @Published private(set) var activeTeenDrives: [ActiveTeenDrive] = []

    private let fileURL: URL
    private weak var accountStore: AccountStore?
    private var localSessions: [TeenTrip] = []
    private var remoteSessionsBySource: [String: [TeenTrip]] = [:]
    private var remoteTeenInfoBySource: [String: ConnectedTeen] = [:]
    private var activeDrivesBySource: [String: ActiveTeenDrive] = [:]
    private var deletedSessionIDs: Set<UUID> = []
    private var listeners: [ListenerRegistration] = []

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init(fileURL: URL? = nil) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? documentsURL.appendingPathComponent("teen-drive-trips.json")
        deletedSessionIDs = Self.loadDeletedSessionIDs()
        Task {
            await load()
        }
    }

    /*
     Purpose:
     Cleans up listeners or resources when this object is released.
    */
    deinit {
        listeners.forEach { $0.remove() }
    }

    /*
     Purpose:
     Attaches the current account store, starts remote listeners, and syncs local trips.
    */
    func configure(accountStore: AccountStore) {
        self.accountStore = accountStore
        Task {
            await accountStore.syncAccount()
            bindRemoteTrips()
            await syncLocalTrips()
        }
    }

    /*
     Purpose:
     Adds a completed local trip, saves it, and schedules cloud sync.
    */
    func add(_ session: TeenTrip) {
        localSessions.insert(session, at: 0)
        mergeSessions()
        save()
        Task {
            await syncTrip(session)
        }
    }

    /*
     Purpose:
     Removes selected trips from local history and deletes matching Firestore trip documents.
    */
    func delete(at offsets: IndexSet) {
        let sessionsToDelete = offsets.compactMap { sessions.indices.contains($0) ? sessions[$0] : nil }
        let idsToDelete = Set(sessionsToDelete.map(\.id))
        deletedSessionIDs.formUnion(idsToDelete)
        saveDeletedSessionIDs()
        localSessions.removeAll { idsToDelete.contains($0.id) }
        remoteSessionsBySource = remoteSessionsBySource.mapValues { sessions in
            sessions.filter { !idsToDelete.contains($0.id) }
        }
        mergeSessions()
        save()

        Task {
            await deleteRemoteTrips(sessionsToDelete)
        }
    }

    /*
     Purpose:
     Sets Firestore listeners for parent trip summaries and active teen drives.
    */
    func bindRemoteTrips() {
        // Parents listen to each connected teen; teens only sync their own local trips.
        removeListeners()
        guard let accountStore,
              let db = FirebaseBackend.shared.database else {
            remoteSessionsBySource = [:]
            mergeSessions()
            return
        }

        if accountStore.role == .parent {
            let connectedTeens = accountStore.connectedTeens.filter {
                !$0.teenProfileID.isEmpty && !$0.familyGroupID.isEmpty
            }
            guard !connectedTeens.isEmpty else {
                remoteSessionsBySource = [:]
                remoteTeenInfoBySource = [:]
                activeDrivesBySource = [:]
                activeTeenDrives = []
                mergeSessions()
                return
            }

            let activeSourceIDs = Set(connectedTeens.map(\.teenProfileID))
            remoteSessionsBySource = remoteSessionsBySource.filter { activeSourceIDs.contains($0.key) }
            remoteTeenInfoBySource = Dictionary(uniqueKeysWithValues: connectedTeens.map { ($0.teenProfileID, $0) })
            activeDrivesBySource = activeDrivesBySource.filter { activeSourceIDs.contains($0.key) }

            for teen in connectedTeens {
                let sourceID = teen.teenProfileID
                let listener = db.collection("familyGroups")
                    .document(teen.familyGroupID)
                    .collection("teens")
                    .document(teen.teenProfileID)
                    .collection("trips")
                    .order(by: "startedAt", descending: true)
                    .addSnapshotListener { [weak self] snapshot, error in
                        Task { @MainActor in
                            if let error {
                                FirebaseBackend.shared.statusMessage = "Could not load parent trips: \((error as NSError).localizedDescription)"
                                self?.remoteSessionsBySource[sourceID] = []
                            } else {
                                self?.remoteSessionsBySource[sourceID] = snapshot?.documents.compactMap(TeenTrip.init(document:)) ?? []
                            }
                            self?.mergeSessions()
                        }
                    }
                listeners.append(listener)

                let activeDriveListener = db.collection("familyGroups")
                    .document(teen.familyGroupID)
                    .collection("teens")
                    .document(teen.teenProfileID)
                    .collection("activeDrive")
                    .document("current")
                    .addSnapshotListener { [weak self] document, _ in
                        Task { @MainActor in
                            if let document,
                               let drive = ActiveTeenDrive(document: document, teen: teen) {
                                self?.activeDrivesBySource[sourceID] = drive
                            } else {
                                self?.activeDrivesBySource.removeValue(forKey: sourceID)
                            }
                            self?.mergeActiveDrives()
                        }
                    }
                listeners.append(activeDriveListener)
            }
        } else {
            remoteTeenInfoBySource = [:]
            guard !accountStore.familyGroupID.isEmpty, !accountStore.teenProfileID.isEmpty else {
                remoteSessionsBySource = [:]
                parentTripSummaries = []
                activeDrivesBySource = [:]
                activeTeenDrives = []
                mergeSessions()
                return
            }
            let sourceID = accountStore.teenProfileID
            let listener = db.collection("familyGroups")
                .document(accountStore.familyGroupID)
                .collection("teens")
                .document(accountStore.teenProfileID)
                .collection("trips")
                .order(by: "startedAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        if let error {
                            FirebaseBackend.shared.statusMessage = "Could not load teen trips: \((error as NSError).localizedDescription)"
                            self?.remoteSessionsBySource[sourceID] = []
                        } else {
                            self?.remoteSessionsBySource[sourceID] = snapshot?.documents.compactMap(TeenTrip.init(document:)) ?? []
                        }
                        self?.mergeSessions()
                    }
                }
            listeners.append(listener)
            parentTripSummaries = []
            activeDrivesBySource = [:]
            activeTeenDrives = []
        }
    }

    /*
     Purpose:
     Attempts to upload all locally saved teen trips to Firestore.
    */
    private func syncLocalTrips() async {
        for session in localSessions {
            await syncTrip(session)
        }
    }

    /*
     Purpose:
     Uploads one completed teen trip document when cloud account IDs are available.
    */
    private func syncTrip(_ session: TeenTrip) async {
        guard !deletedSessionIDs.contains(session.id) else { return }
        guard let accountStore,
              accountStore.role == .teen,
              let db = FirebaseBackend.shared.database,
              !accountStore.familyGroupID.isEmpty,
              !accountStore.teenProfileID.isEmpty else { return }

        do {
            try await db.collection("familyGroups")
                .document(accountStore.familyGroupID)
                .collection("teens")
                .document(accountStore.teenProfileID)
                .collection("trips")
                .document(session.id.uuidString)
                .setData(
                    session.firestoreData(
                        teenID: accountStore.teenProfileID,
                        familyGroupID: accountStore.familyGroupID
                    ),
                    merge: true
                )
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not sync trip"
        }
    }

    /*
     Purpose:
     Deletes synced trip documents so a removed report does not reappear from Firestore listeners.
    */
    private func deleteRemoteTrips(_ sessions: [TeenTrip]) async {
        guard let accountStore,
              let db = FirebaseBackend.shared.database else { return }

        if accountStore.role == .teen,
           !accountStore.familyGroupID.isEmpty,
           !accountStore.teenProfileID.isEmpty {
            for session in sessions {
                await deleteRemoteTrip(
                    sessionID: session.id,
                    familyGroupID: accountStore.familyGroupID,
                    teenProfileID: accountStore.teenProfileID,
                    db: db
                )
            }
            return
        }

        if accountStore.role == .parent {
            for session in sessions {
                let summary = parentTripSummaries.first { $0.trip.id == session.id }
                guard let summary, !summary.familyGroupID.isEmpty else { continue }
                await deleteRemoteTrip(
                    sessionID: session.id,
                    familyGroupID: summary.familyGroupID,
                    teenProfileID: summary.teenProfileID,
                    db: db
                )
            }
        }
    }

    /*
     Purpose:
     Deletes one trip document from the teen's Firestore trip collection.
    */
    private func deleteRemoteTrip(sessionID: UUID, familyGroupID: String, teenProfileID: String, db: Firestore) async {
        do {
            try await db.collection("familyGroups")
                .document(familyGroupID)
                .collection("teens")
                .document(teenProfileID)
                .collection("trips")
                .document(sessionID.uuidString)
                .delete()
        } catch {
            FirebaseBackend.shared.statusMessage = "Could not delete synced trip"
        }
    }

    /*
     Purpose:
     Loads local trip history from disk and merges it into the visible session list.
    */
    private func load() async {
        let diskSessions = await Self.readSessions(from: fileURL)
        var byID = Dictionary(uniqueKeysWithValues: localSessions.map { ($0.id, $0) })
        for session in diskSessions where byID[session.id] == nil {
            byID[session.id] = session
        }
        localSessions = byID.values.sorted { $0.startedAt > $1.startedAt }
        mergeSessions()
    }

    /*
     Purpose:
     Reads and decodes saved trips from the JSON trip history file.
    */
    private static func readSessions(from fileURL: URL) async -> [TeenTrip] {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder.sessionDecoder.decode([TeenTrip].self, from: data)) ?? []
        }.value
    }

    /*
     Purpose:
     Reads the persistent list of deleted report IDs so synced reports stay hidden after restart.
    */
    private static func loadDeletedSessionIDs() -> Set<UUID> {
        let idStrings = UserDefaults.standard.stringArray(forKey: deletedSessionIDsKey) ?? []
        return Set(idStrings.compactMap(UUID.init(uuidString:)))
    }

    /*
     Purpose:
     Saves deleted report IDs as tombstones that stop old cloud snapshots from restoring deleted reports.
    */
    private func saveDeletedSessionIDs() {
        let idStrings = deletedSessionIDs.map(\.uuidString).sorted()
        UserDefaults.standard.set(idStrings, forKey: Self.deletedSessionIDsKey)
    }

    /*
     Purpose:
     Writes local trip history to disk on a background task.
    */
    private func save() {
        do {
            let data = try JSONEncoder.sessionEncoder.encode(localSessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Could not save sessions: \(error.localizedDescription)")
        }
    }

    /*
     Purpose:
     Combines local and remote trips into the arrays shown to teens and parents.
    */
    private func mergeSessions() {
        let visibleRemoteSessionsBySource = remoteSessionsBySource.mapValues { sessions in
            sessions.filter { !deletedSessionIDs.contains($0.id) }
        }
        let remoteSessions = visibleRemoteSessionsBySource.values.flatMap { $0 }
        let visibleLocalSessions = localSessions.filter { !deletedSessionIDs.contains($0.id) }
        let merged = (remoteSessions + visibleLocalSessions).reduce(into: [UUID: TeenTrip]()) { result, session in
            result[session.id] = session
        }
        sessions = merged.values.sorted { $0.startedAt > $1.startedAt }
        parentTripSummaries = visibleRemoteSessionsBySource.flatMap { sourceID, sessions in
            sessions.map { session in
                let teen = remoteTeenInfoBySource[sourceID]
                return ParentTripSummary(
                    teenProfileID: teen?.teenProfileID ?? sourceID,
                    familyGroupID: teen?.familyGroupID ?? "",
                    teenName: teen?.name ?? "Teen",
                    trip: session
                )
            }
        }
        .sorted { $0.trip.startedAt > $1.trip.startedAt }
    }

    /*
     Purpose:
     Sorts active teen drive snapshots by most recent update for the parent dashboard.
    */
    private func mergeActiveDrives() {
        activeTeenDrives = activeDrivesBySource.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /*
     Purpose:
     Detaches Firestore listeners to avoid stale updates and duplicate callbacks.
    */
    private func removeListeners() {
        listeners.forEach { $0.remove() }
        listeners = []
    }
}

private extension JSONDecoder {
    static var sessionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var sessionEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
