import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SpeedSession] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? documentsURL.appendingPathComponent("speed-sessions.json")
        load()
    }

    func add(_ session: SpeedSession) {
        sessions.insert(session, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }

        do {
            sessions = try JSONDecoder.sessionDecoder.decode([SpeedSession].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            sessions = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder.sessionEncoder.encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Could not save sessions: \(error.localizedDescription)")
        }
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
