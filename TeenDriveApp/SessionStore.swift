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
    @Published private(set) var sessions: [TeenTrip] = []
    @Published private(set) var parentTripSummaries: [ParentTripSummary] = []
    @Published private(set) var activeTeenDrives: [ActiveTeenDrive] = []

    private let fileURL: URL
    private weak var accountStore: AccountStore?
    private var localSessions: [TeenTrip] = []
    private var remoteSessionsBySource: [String: [TeenTrip]] = [:]
    private var remoteTeenInfoBySource: [String: ConnectedTeen] = [:]
    private var activeDrivesBySource: [String: ActiveTeenDrive] = [:]
    private var listeners: [ListenerRegistration] = []

    init(fileURL: URL? = nil) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? documentsURL.appendingPathComponent("teen-drive-trips.json")
        Task {
            await load()
        }
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    func configure(accountStore: AccountStore) {
        self.accountStore = accountStore
        Task {
            await accountStore.syncAccount()
            bindRemoteTrips()
            await syncLocalTrips()
        }
    }

    func add(_ session: TeenTrip) {
        localSessions.insert(session, at: 0)
        mergeSessions()
        save()
        Task {
            await syncTrip(session)
        }
    }

    func delete(at offsets: IndexSet) {
        localSessions.remove(atOffsets: offsets)
        mergeSessions()
        save()
    }

    func bindRemoteTrips() {
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

    private func syncLocalTrips() async {
        for session in localSessions {
            await syncTrip(session)
        }
    }

    private func syncTrip(_ session: TeenTrip) async {
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

    private func load() async {
        let diskSessions = await Self.readSessions(from: fileURL)
        var byID = Dictionary(uniqueKeysWithValues: localSessions.map { ($0.id, $0) })
        for session in diskSessions where byID[session.id] == nil {
            byID[session.id] = session
        }
        localSessions = byID.values.sorted { $0.startedAt > $1.startedAt }
        mergeSessions()
    }

    private static func readSessions(from fileURL: URL) async -> [TeenTrip] {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder.sessionDecoder.decode([TeenTrip].self, from: data)) ?? []
        }.value
    }

    private func save() {
        do {
            let data = try JSONEncoder.sessionEncoder.encode(localSessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Could not save sessions: \(error.localizedDescription)")
        }
    }

    private func mergeSessions() {
        let remoteSessions = remoteSessionsBySource.values.flatMap { $0 }
        let merged = (remoteSessions + localSessions).reduce(into: [UUID: TeenTrip]()) { result, session in
            result[session.id] = session
        }
        sessions = merged.values.sorted { $0.startedAt > $1.startedAt }
        parentTripSummaries = remoteSessionsBySource.flatMap { sourceID, sessions in
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

    private func mergeActiveDrives() {
        activeTeenDrives = activeDrivesBySource.values.sorted { $0.updatedAt > $1.updatedAt }
    }

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
