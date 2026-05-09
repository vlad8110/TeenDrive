import ActivityKit
import CoreLocation
import Foundation

@MainActor
final class TeenDriveTracker: NSObject, ObservableObject {
    private let autoStartThresholdMetersPerSecond = 5 / 2.2369362921
    private let autoStopIdleInterval: TimeInterval = 5 * 60
    private let rapidAccelerationThreshold: Double = 2.7
    private let harshStopThreshold: Double = -3.5
    private let drivingEventCooldown: TimeInterval = 30
    private let placeArrivalRadiusMeters: Double = 150

    @Published private(set) var speedMetersPerSecond: Double = 0
    @Published private(set) var topSpeedMetersPerSecond: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var currentTripAlertCount = 0
    @Published private(set) var activeTripStartedAt: Date?
    @Published private(set) var lastKnownLocation: RoutePoint?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    @Published private(set) var isAutoStartArmed = false
    @Published private(set) var statusMessage = "Ready"

    private let locationManager = CLLocationManager()
    private let sessionStore: SessionStore
    private let safetySettings: SafetyAlertSettings
    private let accountStore: AccountStore
    private var previousLocation: CLLocation?
    private var previousSpeedSample: (speed: Double, timestamp: Date)?
    private var startedAt = Date()
    private var lastMovementAt = Date()
    private var route: [RoutePoint] = []
    private var speedAlerts: [SpeedAlert] = []
    private var safetyAlerts: [SafetyAlert] = []
    private var isOverSpeedAlertThreshold = false
    private var lastDrivingEventAt: Date?
    private var visitedPlaceIDs: Set<UUID> = []
    private var liveActivity: Activity<TeenDriveActivityAttributes>?

    init(sessionStore: SessionStore, safetySettings: SafetyAlertSettings, accountStore: AccountStore) {
        self.sessionStore = sessionStore
        self.safetySettings = safetySettings
        self.accountStore = accountStore
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1
        locationManager.pausesLocationUpdatesAutomatically = false
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

    var speedAlertThresholdMPH: Double {
        safetySettings.speedLimitMPH
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func start() {
        start(automatic: false, initialLocation: nil)
    }

    private func start(automatic: Bool, initialLocation: CLLocation?) {
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
        currentTripAlertCount = 0
        lastKnownLocation = nil
        previousLocation = nil
        previousSpeedSample = nil
        route = []
        speedAlerts = []
        safetyAlerts = []
        isOverSpeedAlertThreshold = false
        lastDrivingEventAt = nil
        visitedPlaceIDs = []
        startedAt = Date()
        activeTripStartedAt = startedAt
        lastMovementAt = startedAt
        isTracking = true
        isAutoStartArmed = false
        statusMessage = automatic ? "Drive auto-started" : "Drive tracking"
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        if safetySettings.tripStartedAlertsEnabled {
            recordSafetyAlert(kind: .tripStarted, timestamp: startedAt, note: automatic ? "Auto-started over 5 mph" : "Started manually")
        }
        if let initialLocation {
            handle(location: initialLocation)
        }
        startLiveActivity()
    }

    func stop() {
        stop(reason: "Stopped")
    }

    private func stop(reason: String) {
        if safetySettings.tripEndedAlertsEnabled {
            recordSafetyAlert(kind: .tripEnded, timestamp: Date(), speedMetersPerSecond: speedMetersPerSecond, point: lastKnownLocation, note: reason)
        }
        isTracking = false
        activeTripStartedAt = nil
        statusMessage = reason
        saveSession()
        endLiveActivity()
        armAutoStartIfPossible(statusMessage: reason)
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
        updateIdleState(speedMetersPerSecond: measuredSpeed)
        updateSpeedAlertState(for: location, speedMetersPerSecond: measuredSpeed)
        updateDrivingEventState(for: location, speedMetersPerSecond: measuredSpeed)
        updatePlaceArrivalState(for: location)

        if !isTracking {
            return
        }

        if let previousLocation {
            let segment = location.distance(from: previousLocation)
            if segment.isFinite, segment > 0 {
                distanceMeters += segment
            }
        }

        previousLocation = location
        appendRoutePoint(for: location)
        if !isOverSpeedAlertThreshold {
            statusMessage = location.horizontalAccuracy > 25 ? "Drive tracking, low GPS accuracy" : "Drive tracking"
        }
        updateLiveActivity()
    }

    private func updateSpeedAlertState(for location: CLLocation, speedMetersPerSecond: Double) {
        guard safetySettings.speedAlertsEnabled else {
            isOverSpeedAlertThreshold = false
            return
        }

        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            return
        }

        if speedMetersPerSecond >= safetySettings.speedLimitMPH / 2.2369362921 {
            guard !isOverSpeedAlertThreshold else { return }
            isOverSpeedAlertThreshold = true

            let alert = SpeedAlert(
                timestamp: location.timestamp,
                speedMetersPerSecond: speedMetersPerSecond,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            speedAlerts.append(alert)
            recordSafetyAlert(
                kind: .speedLimit,
                timestamp: location.timestamp,
                speedMetersPerSecond: speedMetersPerSecond,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                note: String(format: "Over %.0f mph limit", safetySettings.speedLimitMPH)
            )
            statusMessage = String(format: "Speed alert: %.0f mph", alert.speedMPH)
        } else {
            isOverSpeedAlertThreshold = false
        }
    }

    private func updateDrivingEventState(for location: CLLocation, speedMetersPerSecond: Double) {
        guard safetySettings.drivingEventAlertsEnabled else {
            previousSpeedSample = (speedMetersPerSecond, location.timestamp)
            return
        }

        defer {
            previousSpeedSample = (speedMetersPerSecond, location.timestamp)
        }

        guard let previousSpeedSample else { return }
        let elapsed = location.timestamp.timeIntervalSince(previousSpeedSample.timestamp)
        guard elapsed >= 1, elapsed <= 10 else { return }

        if let lastDrivingEventAt, location.timestamp.timeIntervalSince(lastDrivingEventAt) < drivingEventCooldown {
            return
        }

        let acceleration = (speedMetersPerSecond - previousSpeedSample.speed) / elapsed
        let kind: SafetyAlertKind?

        if acceleration >= rapidAccelerationThreshold {
            kind = .rapidAcceleration
        } else if acceleration <= harshStopThreshold {
            kind = .harshStop
        } else {
            kind = nil
        }

        guard let kind else { return }
        lastDrivingEventAt = location.timestamp
        recordSafetyAlert(
            kind: kind,
            timestamp: location.timestamp,
            speedMetersPerSecond: speedMetersPerSecond,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            note: String(format: "%.1f m/s²", acceleration)
        )
        statusMessage = kind.title
    }

    private func updatePlaceArrivalState(for location: CLLocation) {
        guard safetySettings.placeArrivalAlertsEnabled else { return }
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }

        for place in safetySettings.savedPlaces where !visitedPlaceIDs.contains(place.id) {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            guard location.distance(from: placeLocation) <= placeArrivalRadiusMeters else { continue }

            visitedPlaceIDs.insert(place.id)
            recordSafetyAlert(
                kind: .placeArrival,
                timestamp: location.timestamp,
                speedMetersPerSecond: speedMetersPerSecond,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                note: place.name
            )
            statusMessage = "Arrived at \(place.name)"
        }
    }

    private func updateIdleState(speedMetersPerSecond: Double) {
        if speedMetersPerSecond >= autoStartThresholdMetersPerSecond {
            lastMovementAt = Date()
            return
        }

        let idleTime = Date().timeIntervalSince(lastMovementAt)
        if idleTime >= autoStopIdleInterval {
            stop(reason: "Auto-stopped after 5 minutes idle")
        }
    }

    private func armAutoStartIfPossible(statusMessage message: String? = nil) {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            isAutoStartArmed = false
            return
        }

        isAutoStartArmed = true
        statusMessage = message ?? "Auto-start armed at 5 mph"
        locationManager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways
        locationManager.startUpdatingLocation()
    }

    private func appendRoutePoint(for location: CLLocation) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            return
        }

        let point = RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp
        )
        route.append(point)
        lastKnownLocation = point
    }

    private func saveSession() {
        guard !route.isEmpty || distanceMeters > 0 else { return }

        let session = TeenTrip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: Date(),
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            speedAlerts: speedAlerts,
            safetyAlerts: safetyAlerts,
            route: route
        )

        sessionStore.add(session)
    }

    private func recordSafetyAlert(
        kind: SafetyAlertKind,
        timestamp: Date,
        speedMetersPerSecond: Double? = nil,
        point: RoutePoint? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        note: String? = nil
    ) {
        let alert = SafetyAlert(
            kind: kind,
            timestamp: timestamp,
            speedMetersPerSecond: speedMetersPerSecond,
            latitude: latitude ?? point?.latitude,
            longitude: longitude ?? point?.longitude,
            note: note
        )
        safetyAlerts.append(alert)
        currentTripAlertCount = safetyAlerts.count
        Task {
            await TeenDriveNotifications.shared.record(alert: alert, accountStore: accountStore)
        }
    }

    private func activityState() -> TeenDriveActivityAttributes.ContentState {
        TeenDriveActivityAttributes.ContentState(
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

        let attributes = TeenDriveActivityAttributes(activityName: "Teen Drive")
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

extension TeenDriveTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
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
