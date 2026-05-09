import CoreLocation
import Foundation
import MapKit

struct RoutePoint: Codable, Hashable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(id: UUID = UUID(), latitude: Double, longitude: Double, timestamp: Date) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct SpeedAlert: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let speedMetersPerSecond: Double
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), timestamp: Date, speedMetersPerSecond: Double, latitude: Double, longitude: Double) {
        self.id = id
        self.timestamp = timestamp
        self.speedMetersPerSecond = speedMetersPerSecond
        self.latitude = latitude
        self.longitude = longitude
    }

    var speedMPH: Double {
        max(speedMetersPerSecond, 0) * 2.2369362921
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum SafetyAlertKind: String, Codable, Hashable {
    case speedLimit
    case rapidAcceleration
    case harshStop
    case tripStarted
    case tripEnded
    case placeArrival

    var title: String {
        switch self {
        case .speedLimit:
            return "Speed over limit"
        case .rapidAcceleration:
            return "Rapid acceleration"
        case .harshStop:
            return "Harsh stop"
        case .tripStarted:
            return "Trip started"
        case .tripEnded:
            return "Trip ended"
        case .placeArrival:
            return "Arrived"
        }
    }

    var systemImage: String {
        switch self {
        case .speedLimit:
            return "speedometer"
        case .rapidAcceleration:
            return "bolt.fill"
        case .harshStop:
            return "exclamationmark.octagon.fill"
        case .tripStarted:
            return "play.fill"
        case .tripEnded:
            return "stop.fill"
        case .placeArrival:
            return "mappin.and.ellipse"
        }
    }
}

struct SafetyAlert: Codable, Hashable, Identifiable {
    let id: UUID
    let kind: SafetyAlertKind
    let timestamp: Date
    let speedMetersPerSecond: Double?
    let latitude: Double?
    let longitude: Double?
    let note: String?

    init(
        id: UUID = UUID(),
        kind: SafetyAlertKind,
        timestamp: Date,
        speedMetersPerSecond: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.speedMetersPerSecond = speedMetersPerSecond
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
    }

    var speedMPH: Double? {
        guard let speedMetersPerSecond else { return nil }
        return max(speedMetersPerSecond, 0) * 2.2369362921
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayText: String {
        if let speedMPH {
            return String(format: "%.0f mph", speedMPH)
        }

        return note ?? kind.title
    }
}

struct TeenTrip: Codable, Hashable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let topSpeedMetersPerSecond: Double
    let speedAlerts: [SpeedAlert]
    let safetyAlerts: [SafetyAlert]
    let route: [RoutePoint]

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        topSpeedMetersPerSecond: Double,
        speedAlerts: [SpeedAlert],
        safetyAlerts: [SafetyAlert],
        route: [RoutePoint]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.topSpeedMetersPerSecond = topSpeedMetersPerSecond
        self.speedAlerts = speedAlerts
        self.safetyAlerts = safetyAlerts
        self.route = route
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case distanceMeters
        case topSpeedMetersPerSecond
        case speedAlerts
        case safetyAlerts
        case route
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        topSpeedMetersPerSecond = try container.decode(Double.self, forKey: .topSpeedMetersPerSecond)
        speedAlerts = try container.decodeIfPresent([SpeedAlert].self, forKey: .speedAlerts) ?? []
        safetyAlerts = try container.decodeIfPresent([SafetyAlert].self, forKey: .safetyAlerts) ?? []
        route = try container.decode([RoutePoint].self, forKey: .route)
    }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var distanceMiles: Double {
        distanceMeters / 1609.344
    }

    var topSpeedMPH: Double {
        max(topSpeedMetersPerSecond, 0) * 2.2369362921
    }

    var safetyAlertCount: Int {
        safetyAlerts.isEmpty ? speedAlerts.count : safetyAlerts.count
    }

    var speedLimitAlertCount: Int {
        displaySafetyAlerts.filter { $0.kind == .speedLimit }.count
    }

    var rapidAccelerationAlertCount: Int {
        displaySafetyAlerts.filter { $0.kind == .rapidAcceleration }.count
    }

    var harshStopAlertCount: Int {
        displaySafetyAlerts.filter { $0.kind == .harshStop }.count
    }

    var drivingEventAlertCount: Int {
        rapidAccelerationAlertCount + harshStopAlertCount
    }

    var displaySafetyAlerts: [SafetyAlert] {
        if !safetyAlerts.isEmpty {
            return safetyAlerts
        }

        return speedAlerts.map { alert in
            SafetyAlert(
                id: alert.id,
                kind: .speedLimit,
                timestamp: alert.timestamp,
                speedMetersPerSecond: alert.speedMetersPerSecond,
                latitude: alert.latitude,
                longitude: alert.longitude,
                note: "Speed alert"
            )
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        route.map(\.coordinate)
    }

    var mapRegion: MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        let bounds = coordinates.reduce(
            (minLat: first.latitude, maxLat: first.latitude, minLon: first.longitude, maxLon: first.longitude)
        ) { bounds, coordinate in
            (
                min(bounds.minLat, coordinate.latitude),
                max(bounds.maxLat, coordinate.latitude),
                min(bounds.minLon, coordinate.longitude),
                max(bounds.maxLon, coordinate.longitude)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: (bounds.minLat + bounds.maxLat) / 2,
            longitude: (bounds.minLon + bounds.maxLon) / 2
        )
        let latitudeDelta = max((bounds.maxLat - bounds.minLat) * 1.5, 0.01)
        let longitudeDelta = max((bounds.maxLon - bounds.minLon) * 1.5, 0.01)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    /// Behavior-based safe score with a transparent penalty breakdown (used on Home and detail).
    var behaviorScoreBreakdown: TripBehaviorScoreBreakdown {
        TripBehaviorScoreBreakdown.compute(for: self)
    }
}

/// Penalty components for the behavior score (single source of truth for UI + “Why this score?”).
struct TripBehaviorScoreBreakdown: Equatable {
    let score: Int
    let topSpeedPenalty: Double
    let speedingPenalty: Double
    let drivingEventPenalty: Double
    let harshStopPenalty: Double
    let alertRatePenalty: Double

    var totalPenalty: Double {
        topSpeedPenalty + speedingPenalty + drivingEventPenalty + harshStopPenalty + alertRatePenalty
    }

    static func compute(for trip: TeenTrip) -> TripBehaviorScoreBreakdown {
        let durationHours = max(trip.duration / 3600, 0.1667)
        let totalAlerts = Double(trip.safetyAlertCount)

        let topSpeedPenalty = min(15, max(0, (trip.topSpeedMPH - 75) * 0.8))
        let speedingPenalty = min(30, Double(trip.speedLimitAlertCount) * 5)
        let drivingEventPenalty = min(28, Double(trip.drivingEventAlertCount) * 7)
        let harshStopPenalty = min(12, Double(trip.harshStopAlertCount) * 4)
        let alertRatePenalty = min(15, (totalAlerts / durationHours) * 1.8)

        let penalty = topSpeedPenalty + speedingPenalty + drivingEventPenalty + harshStopPenalty + alertRatePenalty
        let score = max(0, min(100, Int((100 - penalty).rounded())))
        return TripBehaviorScoreBreakdown(
            score: score,
            topSpeedPenalty: topSpeedPenalty,
            speedingPenalty: speedingPenalty,
            drivingEventPenalty: drivingEventPenalty,
            harshStopPenalty: harshStopPenalty,
            alertRatePenalty: alertRatePenalty
        )
    }
}

extension TimeInterval {
    var durationText: String {
        let totalSeconds = max(Int(self.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
