import FirebaseFirestore
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [TeenTrip] = []

    private let fileURL: URL
    private weak var accountStore: AccountStore?
    private var localSessions: [TeenTrip] = []
    private var remoteSessionsBySource: [String: [TeenTrip]] = [:]
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
                mergeSessions()
                return
            }

            let activeSourceIDs = Set(connectedTeens.map(\.teenProfileID))
            remoteSessionsBySource = remoteSessionsBySource.filter { activeSourceIDs.contains($0.key) }

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
            }
        } else {
            guard !accountStore.familyGroupID.isEmpty, !accountStore.teenProfileID.isEmpty else {
                remoteSessionsBySource = [:]
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
