/*
 File: TeenDriveTracker.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Runs live drive tracking, route capture, safety alert detection, parent live-drive sync, and Lock Screen Live Activity updates.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import ActivityKit
import CoreLocation
import CoreMotion
import FirebaseFirestore
import Foundation

private enum AutoDriveDetectionState {
    case idle
    case possibleDrive
    case driving
    case possibleStop
    case stopped
}

@MainActor
final class TeenDriveTracker: NSObject, ObservableObject {
    // Detection thresholds are intentionally conservative to reduce false positives from GPS noise.
    private let autoStartThresholdMetersPerSecond = 5 / 2.2369362921
    private let autoStopSpeedThresholdMetersPerSecond = 3 / 2.2369362921
    private let autoStartConfirmationInterval: TimeInterval = 15
    private let gpsOnlyAutoStartConfirmationInterval: TimeInterval = 20
    private let autoStopIdleInterval: TimeInterval = 5 * 60
    private let rapidAccelerationThreshold: Double = 3.0
    private let harshStopThreshold: Double = -3.8
    private let harshCorneringThreshold: Double = 3.7
    private let drivingEventCooldown: TimeInterval = 30
    private let phoneUseAlertCooldown: TimeInterval = 5 * 60
    private let speedAlertGraceMPH: Double = 3
    private let speedAlertSustainedInterval: TimeInterval = 3
    private let placeArrivalRadiusMeters: Double = 150

    @Published private(set) var speedMetersPerSecond: Double = 0
    @Published private(set) var topSpeedMetersPerSecond: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var currentTripAlertCount = 0
    @Published private(set) var activeTripStartedAt: Date?
    @Published private(set) var lastKnownLocation: RoutePoint?
    @Published private(set) var currentRoute: [RoutePoint] = []
    @Published private(set) var currentSafetyAlerts: [SafetyAlert] = []
    @Published private(set) var roadSpeedLimitMPH: Double?
    @Published private(set) var roadSpeedLimitRoadName: String?
    @Published private(set) var roadSpeedLimitStatus = "Using fallback alert limit"
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    @Published private(set) var isAutoStartArmed = false
    @Published private(set) var statusMessage = "Ready"

    private let locationManager = CLLocationManager()
    private let sessionStore: SessionStore
    private let safetySettings: SafetyAlertSettings
    private let accountStore: AccountStore
    private let roadSpeedLimitProvider = RoadSpeedLimitProvider()
    private let motionActivityManager = CMMotionActivityManager()
    private var roadSpeedLimitLookupTask: Task<Void, Never>?
    private var currentMotionActivity: CMMotionActivity?
    private var autoDetectionState: AutoDriveDetectionState = .idle
    private var autoStartCandidateStartedAt: Date?
    private var autoStopCandidateStartedAt: Date?
    private var previousLocation: CLLocation?
    private var previousSpeedSample: (speed: Double, timestamp: Date)?
    private var startedAt = Date()
    private var lastMovementAt = Date()
    private var route: [RoutePoint] = []
    private var speedAlerts: [SpeedAlert] = []
    private var safetyAlerts: [SafetyAlert] = []
    private var isOverSpeedAlertThreshold = false
    private var overSpeedStartedAt: Date?
    private var lastDrivingEventAt: Date?
    private var didRecordNightDriving = false
    private var lastPhoneUseAlertAt: Date?
    private var visitedPlaceIDs: Set<UUID> = []
    private var lastVisitArrivalAt: Date?
    private var lastRouteGrowthAt = Date()
    private var lastActiveDriveSyncAt: Date?
    private var liveActivity: Activity<TeenDriveActivityAttributes>?

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init(sessionStore: SessionStore, safetySettings: SafetyAlertSettings, accountStore: AccountStore) {
        self.sessionStore = sessionStore
        self.safetySettings = safetySettings
        self.accountStore = accountStore
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
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
        activeSpeedLimitMPH
    }

    var activeSpeedLimitMPH: Double {
        roadSpeedLimitMPH ?? safetySettings.speedLimitMPH
    }

    var isUsingRoadSpeedLimit: Bool {
        roadSpeedLimitMPH != nil
    }

    var roadSpeedLimitsEnabled: Bool {
        safetySettings.roadSpeedLimitsEnabled
    }

    private var isAutomotiveMotion: Bool {
        guard let activity = currentMotionActivity else { return false }
        return activity.automotive
            && !activity.walking
            && !activity.running
            && !activity.cycling
            && activity.confidence != .low
    }

    private var isStoppedMotion: Bool {
        guard let activity = currentMotionActivity else { return false }
        return activity.stationary || activity.walking || activity.running
    }

    /*
     Purpose:
     Starts Motion & Fitness activity updates so auto-start and auto-stop can combine GPS speed with
     Apple's automotive/stationary classification.
    */
    private func startMotionActivityUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            Task { @MainActor in
                self?.currentMotionActivity = activity
            }
        }
    }

    /*
     Purpose:
     Starts the iOS location permission flow needed for drive tracking.
    */
    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            statusMessage = "Allow location to track drives"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysPermission()
        case .authorizedAlways:
            armAutoStartIfPossible(statusMessage: "Background tracking ready")
        case .denied, .restricted:
            statusMessage = "Enable Location in Settings"
        @unknown default:
            statusMessage = "Location access is needed"
        }
    }

    /*
     Purpose:
     Asks for Always Location permission so auto-start and background tracking can work.
    */
    func requestAlwaysPermission() {
        switch authorizationStatus {
        case .notDetermined:
            statusMessage = "Allow location first"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            statusMessage = "Choose Always Allow for background tracking"
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            armAutoStartIfPossible(statusMessage: "Background tracking ready")
        case .denied, .restricted:
            statusMessage = "Enable Always Location in Settings"
        @unknown default:
            statusMessage = "Location access is needed"
        }
    }

    /*
     Purpose:
     Requests a fresh location sample so the map can center on the current position.
    */
    func centerMapOnCurrentLocation() {
        if authorizationStatus == .notDetermined {
            requestPermission()
            return
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            statusMessage = "Location access is needed"
            return
        }

        locationManager.requestLocation()
        locationManager.startUpdatingLocation()
    }

    /*
     Purpose:
     Begins a new drive either manually or from the auto-start detector.
    */
    func start() {
        start(automatic: false, initialLocation: nil)
    }

    /*
     Purpose:
     Begins a new drive either manually or from the auto-start detector.
    */
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
        currentRoute = []
        currentSafetyAlerts = []
        roadSpeedLimitMPH = nil
        roadSpeedLimitRoadName = nil
        roadSpeedLimitStatus = "Finding road speed limit"
        previousLocation = nil
        previousSpeedSample = nil
        route = []
        speedAlerts = []
        safetyAlerts = []
        isOverSpeedAlertThreshold = false
        overSpeedStartedAt = nil
        lastDrivingEventAt = nil
        didRecordNightDriving = false
        lastPhoneUseAlertAt = nil
        visitedPlaceIDs = []
        autoDetectionState = .driving
        autoStartCandidateStartedAt = nil
        autoStopCandidateStartedAt = nil
        lastVisitArrivalAt = nil
        lastRouteGrowthAt = Date()
        startedAt = Date()
        activeTripStartedAt = startedAt
        lastMovementAt = startedAt
        isTracking = true
        isAutoStartArmed = false
        statusMessage = automatic ? "Drive auto-started" : "Drive tracking"
        startMotionActivityUpdates()
        locationManager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways
        locationManager.startUpdatingLocation()
        if safetySettings.tripStartedAlertsEnabled {
            recordSafetyAlert(kind: .tripStarted, timestamp: startedAt, note: automatic ? "Auto-started over 5 mph" : "Started manually")
        }
        if let initialLocation {
            handle(location: initialLocation)
        }
        syncActiveDrive(force: true)
        startLiveActivity()
    }

    /*
     Purpose:
     Ends the current drive, saves it, clears live state, and rearms auto-start when possible.
    */
    func stop() {
        stop(reason: "Stopped")
    }

    /*
     Purpose:
     Ends the current drive, saves it, clears live state, and rearms auto-start when possible.
    */
    private func stop(reason: String) {
        if safetySettings.tripEndedAlertsEnabled {
            recordSafetyAlert(kind: .tripEnded, timestamp: Date(), speedMetersPerSecond: speedMetersPerSecond, point: lastKnownLocation, note: reason)
        }
        isTracking = false
        activeTripStartedAt = nil
        autoDetectionState = .stopped
        autoStartCandidateStartedAt = nil
        autoStopCandidateStartedAt = nil
        statusMessage = reason
        saveSession()
        clearActiveDrive()
        endLiveActivity()
        armAutoStartIfPossible(statusMessage: reason)
    }

    /*
     Purpose:
     Processes one location sample and updates speed, route, alerts, live sync, and Live Activity state.
    */
    private func handle(location: CLLocation) {
        // One location sample drives speed display, auto-start, alert checks, route history, and sync.
        let measuredSpeed = max(location.speed, 0)
        speedMetersPerSecond = measuredSpeed

        updateLiveLocation(for: location)
        updateRoadSpeedLimitIfNeeded(for: location)

        guard isTracking else {
            if shouldAutoStart(from: location, speedMetersPerSecond: measuredSpeed) {
                start(automatic: true, initialLocation: location)
            }
            return
        }

        topSpeedMetersPerSecond = max(topSpeedMetersPerSecond, measuredSpeed)
        updateIdleState(for: location, speedMetersPerSecond: measuredSpeed)
        updateSpeedAlertState(for: location, speedMetersPerSecond: measuredSpeed)
        updateDrivingEventState(for: location, speedMetersPerSecond: measuredSpeed)
        updateCorneringEventState(for: location, speedMetersPerSecond: measuredSpeed)
        updateNightDrivingState(for: location)
        updatePlaceArrivalState(for: location)

        if !isTracking {
            return
        }

        if let previousLocation {
            let segment = location.distance(from: previousLocation)
            if segment.isFinite, segment > 0 {
                distanceMeters += segment
                if segment >= 10 {
                    lastRouteGrowthAt = location.timestamp
                }
            }
        }

        previousLocation = location
        appendRoutePoint(for: location)
        if !isOverSpeedAlertThreshold {
            statusMessage = location.horizontalAccuracy > 25 ? "Drive tracking, low GPS accuracy" : "Drive tracking"
        }
        syncActiveDrive()
        updateLiveActivity()
    }

    /*
     Purpose:
     Detects sustained speeding above the active road or fallback limit.
    */
    private func updateSpeedAlertState(for location: CLLocation, speedMetersPerSecond: Double) {
        // Require a small grace amount and a short sustained interval before recording speeding.
        guard safetySettings.speedAlertsEnabled else {
            isOverSpeedAlertThreshold = false
            overSpeedStartedAt = nil
            return
        }

        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            return
        }

        let speedLimitMPH = activeSpeedLimitMPH
        let speedMPH = speedMetersPerSecond * 2.2369362921
        if speedMPH >= speedLimitMPH + speedAlertGraceMPH {
            let thresholdStartedAt = overSpeedStartedAt ?? location.timestamp
            overSpeedStartedAt = thresholdStartedAt
            guard location.timestamp.timeIntervalSince(thresholdStartedAt) >= speedAlertSustainedInterval else { return }
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
                note: String(format: "Over %.0f mph limit", speedLimitMPH)
            )
            statusMessage = String(format: "Speed alert: %.0f mph in %.0f", alert.speedMPH, speedLimitMPH)
        } else {
            isOverSpeedAlertThreshold = false
            overSpeedStartedAt = nil
        }
    }

    /*
     Purpose:
     Detects rapid acceleration and harsh braking from consecutive speed samples.
    */
    private func updateDrivingEventState(for location: CLLocation, speedMetersPerSecond: Double) {
        // Acceleration and braking are calculated from consecutive speed samples.
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

    /*
     Purpose:
     Detects harsh cornering by estimating lateral acceleration from speed and heading change.
    */
    private func updateCorneringEventState(for location: CLLocation, speedMetersPerSecond: Double) {
        // Harsh cornering estimates lateral acceleration from speed and heading change.
        guard safetySettings.drivingEventAlertsEnabled else { return }
        guard let previousLocation,
              previousLocation.course >= 0,
              location.course >= 0,
              speedMetersPerSecond >= 20 / 2.2369362921 else {
            return
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsed >= 1, elapsed <= 10 else { return }
        if let lastDrivingEventAt, location.timestamp.timeIntervalSince(lastDrivingEventAt) < drivingEventCooldown {
            return
        }

        let headingDelta = Self.smallestAngleDeltaDegrees(from: previousLocation.course, to: location.course)
        let lateralAcceleration = speedMetersPerSecond * abs(headingDelta * .pi / 180) / elapsed
        guard lateralAcceleration >= harshCorneringThreshold else { return }

        lastDrivingEventAt = location.timestamp
        recordSafetyAlert(
            kind: .harshCornering,
            timestamp: location.timestamp,
            speedMetersPerSecond: speedMetersPerSecond,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            note: String(format: "%.2fg turn", lateralAcceleration / 9.80665)
        )
        statusMessage = "Harsh cornering"
    }

    /*
     Purpose:
     Records a once-per-trip alert when driving happens during the configured night window.
    */
    private func updateNightDrivingState(for location: CLLocation) {
        guard safetySettings.nightDrivingAlertsEnabled, !didRecordNightDriving else { return }
        guard Self.isNightDrivingTime(location.timestamp) else { return }

        didRecordNightDriving = true
        recordSafetyAlert(
            kind: .nightDriving,
            timestamp: location.timestamp,
            speedMetersPerSecond: speedMetersPerSecond,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            note: "Driving between 10 PM and 5 AM"
        )
        statusMessage = "Night driving"
    }

    /*
     Purpose:
     Records phone-use alerts when the app or unlock signal appears during active driving.
    */
    func recordPhoneUseIfDriving(reason: String = "App opened while moving") {
        // iOS does not expose exact phone-use details, so this records strong app/unlock signals.
        guard safetySettings.phoneUseAlertsEnabled, isTracking else { return }
        guard Date().timeIntervalSince(startedAt) >= 30, speedMPH >= 10 else { return }
        if let lastPhoneUseAlertAt, Date().timeIntervalSince(lastPhoneUseAlertAt) < phoneUseAlertCooldown {
            return
        }

        let now = Date()
        lastPhoneUseAlertAt = now
        recordSafetyAlert(
            kind: .phoneUse,
            timestamp: now,
            speedMetersPerSecond: speedMetersPerSecond,
            point: lastKnownLocation,
            note: reason
        )
        statusMessage = "Phone use while moving"
    }

    /*
     Purpose:
     Records arrival alerts when the teen enters the radius of a saved place.
    */
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

    /*
     Purpose:
     Refreshes the current road speed limit when GPS quality is good enough.
    */
    private func updateRoadSpeedLimitIfNeeded(for location: CLLocation) {
        guard safetySettings.roadSpeedLimitsEnabled,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else {
            roadSpeedLimitMPH = nil
            roadSpeedLimitRoadName = nil
            roadSpeedLimitStatus = "Using fallback alert limit"
            return
        }

        guard roadSpeedLimitLookupTask == nil else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        roadSpeedLimitLookupTask = Task { [roadSpeedLimitProvider] in
            let lookup = await roadSpeedLimitProvider.lookup(latitude: latitude, longitude: longitude)
            await MainActor.run {
                roadSpeedLimitLookupTask = nil
                roadSpeedLimitMPH = lookup.limitMPH
                roadSpeedLimitRoadName = lookup.roadName
                roadSpeedLimitStatus = lookup.sourceDescription
            }
        }
    }

    /*
     Purpose:
     Starts a drive only after GPS and motion agree long enough to avoid one-sample false starts.
    */
    private func shouldAutoStart(from location: CLLocation, speedMetersPerSecond: Double) -> Bool {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            resetAutoStartCandidate()
            return false
        }

        let motionAvailable = CMMotionActivityManager.isActivityAvailable()
        let motionAllowsStart = isAutomotiveMotion || !motionAvailable || currentMotionActivity == nil
        guard speedMetersPerSecond >= autoStartThresholdMetersPerSecond, motionAllowsStart else {
            resetAutoStartCandidate()
            return false
        }

        let now = location.timestamp
        if autoStartCandidateStartedAt == nil {
            autoStartCandidateStartedAt = now
            autoDetectionState = .possibleDrive
            statusMessage = isAutomotiveMotion ? "Possible drive detected" : "Checking movement"
            return false
        }

        let requiredInterval = isAutomotiveMotion ? autoStartConfirmationInterval : gpsOnlyAutoStartConfirmationInterval
        guard now.timeIntervalSince(autoStartCandidateStartedAt ?? now) >= requiredInterval else {
            return false
        }

        resetAutoStartCandidate()
        return true
    }

    /*
     Purpose:
     Stops the trip automatically after speed, motion, and route changes show the drive has really ended.
    */
    private func updateIdleState(for location: CLLocation, speedMetersPerSecond: Double) {
        if speedMetersPerSecond >= autoStartThresholdMetersPerSecond || isAutomotiveMotion {
            lastMovementAt = location.timestamp
            autoStopCandidateStartedAt = nil
            if isTracking {
                autoDetectionState = .driving
            }
            return
        }

        let now = location.timestamp
        let stoppedBySpeed = speedMetersPerSecond <= autoStopSpeedThresholdMetersPerSecond
        let stoppedByMotion = isStoppedMotion
        let stoppedByVisit = lastVisitArrivalAt.map { now.timeIntervalSince($0) <= autoStopIdleInterval } ?? false
        let routeHasGoneQuiet = now.timeIntervalSince(lastRouteGrowthAt) >= autoStopIdleInterval
        guard stoppedBySpeed, stoppedByMotion || stoppedByVisit || routeHasGoneQuiet else {
            autoStopCandidateStartedAt = nil
            return
        }

        if autoStopCandidateStartedAt == nil {
            autoStopCandidateStartedAt = max(lastMovementAt, now)
            autoDetectionState = .possibleStop
            statusMessage = "Checking if drive ended"
        }

        let idleTime = now.timeIntervalSince(autoStopCandidateStartedAt ?? now)
        if idleTime >= autoStopIdleInterval {
            stop(reason: stoppedByVisit ? "Auto-stopped after arrival" : "Auto-stopped after 5 minutes idle")
        }
    }

    /*
     Purpose:
     Clears pending auto-start evidence when speed or motion no longer looks like a drive.
    */
    private func resetAutoStartCandidate() {
        autoStartCandidateStartedAt = nil
        if !isTracking {
            autoDetectionState = .idle
        }
    }

    /*
     Purpose:
     Prepares background location updates so a future drive can auto-start.
    */
    private func armAutoStartIfPossible(statusMessage message: String? = nil) {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            isAutoStartArmed = false
            return
        }

        isAutoStartArmed = true
        statusMessage = message ?? "Auto-start armed at 5 mph"
        startMotionActivityUpdates()
        locationManager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        if authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    /*
     Purpose:
     Adds a valid GPS point to the current trip route and published route state.
    */
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
        currentRoute = route
        lastKnownLocation = point
    }

    /*
     Purpose:
     Publishes the latest valid GPS coordinate for maps and phone-use alert locations.
    */
    private func updateLiveLocation(for location: CLLocation) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else {
            return
        }

        let point = RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp
        )
        lastKnownLocation = point
    }

    /*
     Purpose:
     Builds a completed TeenTrip from current drive state and stores it in the session store.
    */
    private func saveSession() {
        let reportRoute = route.isEmpty ? fallbackReportRoute() : route
        guard !reportRoute.isEmpty || distanceMeters > 0 || !safetyAlerts.isEmpty else {
            statusMessage = "Drive stopped before any report data was captured"
            return
        }

        let session = TeenTrip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: Date(),
            distanceMeters: distanceMeters,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            speedAlerts: speedAlerts,
            safetyAlerts: safetyAlerts,
            route: reportRoute
        )

        sessionStore.add(session)
        statusMessage = "Drive report saved"
    }

    /*
     Purpose:
     Creates a minimal route for very short drives when GPS produced a current location but no accepted route point yet.

     This keeps manual start/stop and short neighborhood tests from disappearing from Reports. Longer drives still use
     their full sampled route.
    */
    private func fallbackReportRoute() -> [RoutePoint] {
        guard let lastKnownLocation else { return [] }
        return [
            RoutePoint(
                latitude: lastKnownLocation.latitude,
                longitude: lastKnownLocation.longitude,
                timestamp: startedAt
            ),
            RoutePoint(
                latitude: lastKnownLocation.latitude,
                longitude: lastKnownLocation.longitude,
                timestamp: Date()
            )
        ]
    }

    /*
     Purpose:
     Creates a safety alert, updates live counts, syncs parents, and triggers notifications.
    */
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
        let displayAlerts = safetyAlerts.filter { $0.kind.countsAsSafetyAlert }
        currentSafetyAlerts = displayAlerts
        currentTripAlertCount = displayAlerts.count
        syncActiveDrive(force: true)
        Task {
            await TeenDriveNotifications.shared.record(alert: alert, accountStore: accountStore)
        }
    }

    /*
     Purpose:
     Writes the teen active-drive snapshot used by the parent live dashboard.
    */
    private func syncActiveDrive(force: Bool = false) {
        // Active-drive documents power the parent's live map and are throttled to save writes.
        guard isTracking,
              accountStore.role == .teen,
              let db = FirebaseBackend.shared.database,
              !accountStore.familyGroupID.isEmpty,
              !accountStore.teenProfileID.isEmpty else {
            return
        }

        let now = Date()
        if !force,
           let lastActiveDriveSyncAt,
           now.timeIntervalSince(lastActiveDriveSyncAt) < 5 {
            return
        }
        lastActiveDriveSyncAt = now

        let displayName = accountStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routeSnapshot = Array(route.suffix(160))
        let alertSnapshot = Array(safetyAlerts.filter { $0.kind.countsAsSafetyAlert }.suffix(60))
        var data: [String: Any] = [
            "isActive": true,
            "teenID": accountStore.teenProfileID,
            "teenName": displayName.isEmpty ? "Teen" : displayName,
            "startedAt": Timestamp(date: startedAt),
            "updatedAt": Timestamp(date: now),
            "speedMetersPerSecond": speedMetersPerSecond,
            "topSpeedMetersPerSecond": topSpeedMetersPerSecond,
            "distanceMeters": distanceMeters,
            "alertCount": currentTripAlertCount,
            "safetyAlerts": alertSnapshot.map(\.firestoreData),
            "route": routeSnapshot.map(\.firestoreData)
        ]
        if let lastKnownLocation {
            data["lastKnownLocation"] = lastKnownLocation.firestoreData
        }

        Task {
            do {
                let familyGroupID = await accountStore.resolveParentLinkedFamilyGroupID(db: db)
                guard !familyGroupID.isEmpty else { return }
                data["familyGroupID"] = familyGroupID
                try await db.collection("familyGroups")
                    .document(familyGroupID)
                    .collection("teens")
                    .document(accountStore.teenProfileID)
                    .collection("activeDrive")
                    .document("current")
                    .setData(data, merge: true)
            } catch {
                FirebaseBackend.shared.statusMessage = "Could not sync live drive"
            }
        }
    }

    /*
     Purpose:
     Marks the teen active-drive document inactive after a trip ends.
    */
    private func clearActiveDrive() {
        guard accountStore.role == .teen,
              let db = FirebaseBackend.shared.database,
              !accountStore.familyGroupID.isEmpty,
              !accountStore.teenProfileID.isEmpty else {
            return
        }

        var data: [String: Any] = [
            "isActive": false,
            "teenID": accountStore.teenProfileID,
            "updatedAt": Timestamp(date: Date()),
            "endedAt": Timestamp(date: Date())
        ]

        Task {
            do {
                let familyGroupID = await accountStore.resolveParentLinkedFamilyGroupID(db: db)
                guard !familyGroupID.isEmpty else { return }
                data["familyGroupID"] = familyGroupID
                try await db.collection("familyGroups")
                    .document(familyGroupID)
                    .collection("teens")
                    .document(accountStore.teenProfileID)
                    .collection("activeDrive")
                    .document("current")
                    .setData(data, merge: true)
            } catch {
                FirebaseBackend.shared.statusMessage = "Could not clear live drive"
            }
        }
    }

    /*
     Purpose:
     Builds the small state payload displayed by the Lock Screen Live Activity.
    */
    private func activityState() -> TeenDriveActivityAttributes.ContentState {
        TeenDriveActivityAttributes.ContentState(
            speedMetersPerSecond: speedMetersPerSecond,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            distanceMeters: distanceMeters
        )
    }

    /*
     Purpose:
     Starts or reuses the Lock Screen Live Activity for the current drive.
    */
    private func startLiveActivity() {
        // Reuse any existing activity after relaunch so the lock-screen card does not duplicate.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusMessage = "Live Activities are unavailable"
            return
        }

        let existingActivities: [Activity<TeenDriveActivityAttributes>] = Activity.activities
        if let existingActivity = existingActivities.first {
            liveActivity = existingActivity
            updateLiveActivity()

            let duplicateActivities = existingActivities.dropFirst()
            guard !duplicateActivities.isEmpty else { return }

            let content = ActivityContent(state: activityState(), staleDate: nil)
            Task {
                for activity in duplicateActivities {
                    await activity.end(content, dismissalPolicy: .immediate)
                }
            }
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

    /*
     Purpose:
     Pushes the latest speed, top speed, and distance into the Live Activity.
    */
    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let content = ActivityContent(state: activityState(), staleDate: Date().addingTimeInterval(60))

        Task {
            await liveActivity.update(content)
        }
    }

    /*
     Purpose:
     Ends any active Teen Drive Live Activity when tracking stops.
    */
    private func endLiveActivity() {
        guard let liveActivity else {
            let activities: [Activity<TeenDriveActivityAttributes>] = Activity.activities
            guard !activities.isEmpty else { return }

            let content = ActivityContent(state: activityState(), staleDate: nil)
            Task {
                for activity in activities {
                    await activity.end(content, dismissalPolicy: .default)
                }
            }
            return
        }

        self.liveActivity = nil
        let content = ActivityContent(state: activityState(), staleDate: nil)

        Task {
            await liveActivity.end(content, dismissalPolicy: .default)
            let activities: [Activity<TeenDriveActivityAttributes>] = Activity.activities
            for activity in activities where activity.id != liveActivity.id {
                await activity.end(content, dismissalPolicy: .default)
            }
        }
    }

    /*
     Purpose:
     Returns the signed shortest heading change between two compass bearings.
    */
    private static func smallestAngleDeltaDegrees(from start: CLLocationDirection, to end: CLLocationDirection) -> Double {
        let delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            return delta - 360
        }
        if delta < -180 {
            return delta + 360
        }
        return delta
    }

    /*
     Purpose:
     Checks whether a timestamp falls inside the night-driving alert window.
    */
    private static func isNightDrivingTime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 5
    }
}

extension TeenDriveTracker: CLLocationManagerDelegate {
    /*
     Purpose:
     Responds to location permission changes from iOS.
    */
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedAlways:
                armAutoStartIfPossible(statusMessage: "Background tracking ready")
            case .authorizedWhenInUse:
                statusMessage = "Enable Always Location for background tracking"
            case .denied, .restricted:
                isAutoStartArmed = false
                statusMessage = "Location access is needed"
            case .notDetermined:
                statusMessage = "Ready"
            @unknown default:
                statusMessage = "Location status changed"
            }
        }
    }

    /*
     Purpose:
     Receives location updates or location errors from Core Location.
    */
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            handle(location: location)
        }
    }

    /*
     Purpose:
     Uses iOS visit-arrival events as an extra hint that a drive has ended at a real destination.
    */
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            guard visit.arrivalDate != .distantPast else { return }
            lastVisitArrivalAt = visit.arrivalDate
            if isTracking {
                autoStopCandidateStartedAt = autoStopCandidateStartedAt ?? visit.arrivalDate
                autoDetectionState = .possibleStop
                statusMessage = "Arrival detected"
            }
        }
    }

    /*
     Purpose:
     Receives location updates or location errors from Core Location.
    */
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = error.localizedDescription
        }
    }
}
