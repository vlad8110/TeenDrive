import ActivityKit
import CoreLocation
import Foundation

@MainActor
final class SpeedTracker: NSObject, ObservableObject {
    private let autoStartThresholdMetersPerSecond = 5 / 2.2369362921

    @Published private(set) var speedMetersPerSecond: Double = 0
    @Published private(set) var topSpeedMetersPerSecond: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    @Published private(set) var isAutoStartArmed = false
    @Published private(set) var statusMessage = "Ready"

    private let locationManager = CLLocationManager()
    private let sessionStore: SessionStore
    private var previousLocation: CLLocation?
    private var startedAt = Date()
    private var route: [RoutePoint] = []
    private var liveActivity: Activity<SpeedActivityAttributes>?

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1
        locationManager.pausesLocationUpdatesAutomatically = false
        armAutoStartIfPossible()
    }

    var speedMPH: Double {
        max(speedMetersPerSecond, 0) * 2.2369362921
    }

    var topSpeedMPH: Double {
        max(topSpeedMetersPerSecond, 0) * 2.2369362921
    }

    var distanceMiles: Double {
        distanceMeters / 1609.344
    }

    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func start() {
        start(automatic: false, initialLocation: nil)
    }

    private func start(automatic: Bool, initialLocation: CLLocation?) {
        guard CLLocationManager.locationServicesEnabled() else {
            statusMessage = "Location services are off"
            return
        }

        if authorizationStatus == .notDetermined {
            requestPermission()
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            statusMessage = "Location access is needed"
            return
        }

        speedMetersPerSecond = 0
        topSpeedMetersPerSecond = 0
        distanceMeters = 0
        previousLocation = nil
        route = []
        startedAt = Date()
        isTracking = true
        isAutoStartArmed = false
        statusMessage = automatic ? "Auto tracking started" : "Tracking speed"
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        if let initialLocation {
            handle(location: initialLocation)
        }
        startLiveActivity()
    }

    func stop() {
        isTracking = false
        statusMessage = "Stopped"
        saveSession()
        endLiveActivity()
        armAutoStartIfPossible()
    }

    private func handle(location: CLLocation) {
        let measuredSpeed = max(location.speed, 0)
        speedMetersPerSecond = measuredSpeed

        guard isTracking else {
            if measuredSpeed >= autoStartThresholdMetersPerSecond {
                start(automatic: true, initialLocation: location)
            }
            return
        }

        topSpeedMetersPerSecond = max(topSpeedMetersPerSecond, measuredSpeed)

        if let previousLocation {
            let segment = location.distance(from: previousLocation)
            if segment.isFinite, segment > 0 {
                distanceMeters += segment
            }
        }

        previousLocation = location
        appendRoutePoint(for: location)
        statusMessage = location.horizontalAccuracy > 25 ? "Tracking, low GPS accuracy" : "Tracking speed"
        updateLiveActivity()
    }

    private func armAutoStartIfPossible() {
        guard CLLocationManager.locationServicesEnabled() else {
            isAutoStartArmed = false
            statusMessage = "Location services are off"
            return
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            isAutoStartArmed = false
            return
        }

        isAutoStartArmed = true
        statusMessage = "Auto-start armed at 5 mph"
        locationManager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways
        locationManager.startUpdatingLocation()
    }

    private func appendRoutePoint(for location: CLLocation) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            return
        }

        route.append(
            RoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp
            )
        )
    }

    private func saveSession() {
        guard !route.isEmpty || distanceMeters > 0 else { return }

        let session = SpeedSession(
            id: UUID(),
            startedAt: startedAt,
            endedAt: Date(),
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            route: route
        )

        sessionStore.add(session)
    }

    private func activityState() -> SpeedActivityAttributes.ContentState {
        SpeedActivityAttributes.ContentState(
            speedMetersPerSecond: speedMetersPerSecond,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            distanceMeters: distanceMeters,
            startedAt: startedAt,
            updatedAt: Date()
        )
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusMessage = "Live Activities are unavailable"
            return
        }

        let attributes = SpeedActivityAttributes(activityName: "Speed")
        let content = ActivityContent(state: activityState(), staleDate: Date().addingTimeInterval(60))

        do {
            liveActivity = try Activity.request(attributes: attributes, content: content)
        } catch {
            statusMessage = "Could not start Live Activity"
        }
    }

    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let content = ActivityContent(state: activityState(), staleDate: Date().addingTimeInterval(60))

        Task {
            await liveActivity.update(content)
        }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        self.liveActivity = nil
        let content = ActivityContent(state: activityState(), staleDate: nil)

        Task {
            await liveActivity.end(content, dismissalPolicy: .default)
        }
    }
}

extension SpeedTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                armAutoStartIfPossible()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            handle(location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = error.localizedDescription
        }
    }
}
