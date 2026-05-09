import FirebaseFirestore
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [TeenTrip] = []

    private let fileURL: URL
    private weak var accountStore: AccountStore?
    private var localSessions: [TeenTrip] = []
    private var remoteSessions: [TeenTrip] = []
    private var listener: ListenerRegistration?

    init(fileURL: URL? = nil) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? documentsURL.appendingPathComponent("teen-drive-trips.json")
        load()
    }

    deinit {
        listener?.remove()
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
        listener?.remove()
        guard let accountStore,
              let db = FirebaseBackend.shared.database else {
            remoteSessions = []
            mergeSessions()
            return
        }

        if accountStore.role == .parent {
            let teenIDs = Array(Set(accountStore.connectedTeens.map(\.teenProfileID).filter { !$0.isEmpty }))
            guard !teenIDs.isEmpty else {
                remoteSessions = []
                mergeSessions()
                return
            }

            listener = db.collectionGroup("trips")
                .whereField("teenID", in: Array(teenIDs.prefix(10)))
                .addSnapshotListener { [weak self] snapshot, _ in
                    Task { @MainActor in
                        self?.remoteSessions = snapshot?.documents.compactMap(TeenTrip.init(document:)) ?? []
                        self?.mergeSessions()
                    }
                }
        } else {
            guard !accountStore.familyGroupID.isEmpty, !accountStore.teenProfileID.isEmpty else { return }
            listener = db.collection("familyGroups")
                .document(accountStore.familyGroupID)
                .collection("teens")
                .document(accountStore.teenProfileID)
                .collection("trips")
                .order(by: "startedAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, _ in
                    Task { @MainActor in
                        self?.remoteSessions = snapshot?.documents.compactMap(TeenTrip.init(document:)) ?? []
                        self?.mergeSessions()
                    }
                }
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }

        do {
            localSessions = try JSONDecoder.sessionDecoder.decode([TeenTrip].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
            mergeSessions()
        } catch {
            localSessions = []
            mergeSessions()
        }
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
        let merged = (remoteSessions + localSessions).reduce(into: [UUID: TeenTrip]()) { result, session in
            result[session.id] = session
        }
        sessions = merged.values.sorted { $0.startedAt > $1.startedAt }
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
