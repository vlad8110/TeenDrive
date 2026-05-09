import Foundation

struct SavedPlace: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

@MainActor
final class SafetyAlertSettings: ObservableObject {
    @Published var speedAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(speedAlertsEnabled, forKey: Keys.speedAlertsEnabled) }
    }

    @Published var drivingEventAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(drivingEventAlertsEnabled, forKey: Keys.drivingEventAlertsEnabled) }
    }

    @Published var tripStartedAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(tripStartedAlertsEnabled, forKey: Keys.tripStartedAlertsEnabled) }
    }

    @Published var tripEndedAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(tripEndedAlertsEnabled, forKey: Keys.tripEndedAlertsEnabled) }
    }

    @Published var placeArrivalAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(placeArrivalAlertsEnabled, forKey: Keys.placeArrivalAlertsEnabled) }
    }

    @Published var speedLimitMPH: Double {
        didSet { UserDefaults.standard.set(speedLimitMPH, forKey: Keys.speedLimitMPH) }
    }

    @Published private(set) var savedPlaces: [SavedPlace] {
        didSet { savePlaces() }
    }

    init() {
        let defaults = UserDefaults.standard
        speedAlertsEnabled = defaults.object(forKey: Keys.speedAlertsEnabled) as? Bool ?? true
        drivingEventAlertsEnabled = defaults.object(forKey: Keys.drivingEventAlertsEnabled) as? Bool ?? true
        tripStartedAlertsEnabled = defaults.object(forKey: Keys.tripStartedAlertsEnabled) as? Bool ?? true
        tripEndedAlertsEnabled = defaults.object(forKey: Keys.tripEndedAlertsEnabled) as? Bool ?? true
        placeArrivalAlertsEnabled = defaults.object(forKey: Keys.placeArrivalAlertsEnabled) as? Bool ?? true
        speedLimitMPH = defaults.object(forKey: Keys.speedLimitMPH) as? Double ?? 75

        if let data = defaults.data(forKey: Keys.savedPlaces),
           let places = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            savedPlaces = places
        } else {
            savedPlaces = []
        }
    }

    func savePlace(named name: String, point: RoutePoint) {
        let place = SavedPlace(name: name, latitude: point.latitude, longitude: point.longitude)
        savedPlaces.removeAll { $0.name == name }
        savedPlaces.append(place)
        savedPlaces.sort { $0.name < $1.name }
    }

    func deletePlaces(at offsets: IndexSet) {
        savedPlaces.remove(atOffsets: offsets)
    }

    private func savePlaces() {
        guard let data = try? JSONEncoder().encode(savedPlaces) else { return }
        UserDefaults.standard.set(data, forKey: Keys.savedPlaces)
    }
}

private enum Keys {
    static let speedAlertsEnabled = "safety.speedAlertsEnabled"
    static let drivingEventAlertsEnabled = "safety.drivingEventAlertsEnabled"
    static let tripStartedAlertsEnabled = "safety.tripStartedAlertsEnabled"
    static let tripEndedAlertsEnabled = "safety.tripEndedAlertsEnabled"
    static let placeArrivalAlertsEnabled = "safety.placeArrivalAlertsEnabled"
    static let speedLimitMPH = "safety.speedLimitMPH"
    static let savedPlaces = "safety.savedPlaces"
}
