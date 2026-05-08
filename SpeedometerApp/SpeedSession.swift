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

struct SpeedSession: Codable, Hashable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let topSpeedMetersPerSecond: Double
    let route: [RoutePoint]

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var distanceMiles: Double {
        distanceMeters / 1609.344
    }

    var topSpeedMPH: Double {
        max(topSpeedMetersPerSecond, 0) * 2.2369362921
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
