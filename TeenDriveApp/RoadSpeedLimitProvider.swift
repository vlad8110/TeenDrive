/*
 File: RoadSpeedLimitProvider.swift
 Created: 2026-05-10
 Creator: Vladimyr Merci

 Purpose:
 Queries OpenStreetMap Overpass for nearby road speed limits and caches results for live speed alerts.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import Foundation

struct RoadSpeedLimitLookup: Equatable, Sendable {
    var limitMPH: Double?
    var roadName: String?
    var sourceDescription: String
}

actor RoadSpeedLimitProvider {
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    private let searchRadiusMeters = 90.0
    private let minimumLookupInterval: TimeInterval = 12
    private let cacheDistanceMeters = 75.0
    private let cacheTTL: TimeInterval = 75
    private var lastLookup: CachedLookup?

    /*
     Purpose:
     Returns a cached or newly fetched road speed limit near the provided coordinate.
    */
    func lookup(latitude: Double, longitude: Double) async -> RoadSpeedLimitLookup {
        // Road-limit lookups are throttled and cached so location updates do not spam Overpass.
        let now = Date()
        if let cached = lastLookup {
            let distance = Self.distanceMeters(
                fromLatitude: latitude,
                longitude: longitude,
                toLatitude: cached.latitude,
                longitude: cached.longitude
            )
            if distance <= cacheDistanceMeters, now.timeIntervalSince(cached.timestamp) <= cacheTTL {
                return cached.result
            }

            if now.timeIntervalSince(cached.timestamp) < minimumLookupInterval {
                return cached.result
            }
        }

        let result = await fetchSpeedLimit(latitude: latitude, longitude: longitude)
        lastLookup = CachedLookup(latitude: latitude, longitude: longitude, timestamp: now, result: result)
        return result
    }

    /*
     Purpose:
     Calls the Overpass API and decodes nearby mapped roads with speed-limit tags.
    */
    private func fetchSpeedLimit(latitude: Double, longitude: Double) async -> RoadSpeedLimitLookup {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("TeenDrive/1.0 road-speed-limit lookup", forHTTPHeaderField: "User-Agent")

        let query = """
        [out:json][timeout:6];
        way(around:\(Int(searchRadiusMeters)),\(latitude),\(longitude))["highway"]["maxspeed"];
        out tags geom qt;
        """
        request.httpBody = "data=\(Self.formEncoded(query))".data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return RoadSpeedLimitLookup(limitMPH: nil, roadName: nil, sourceDescription: "Road speed lookup unavailable")
            }

            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            return Self.bestLimit(from: decoded.elements, latitude: latitude, longitude: longitude)
        } catch {
            return RoadSpeedLimitLookup(limitMPH: nil, roadName: nil, sourceDescription: "Road speed lookup unavailable")
        }
    }

    /*
     Purpose:
     Chooses the closest driveable road speed limit from the Overpass response.
    */
    private static func bestLimit(from elements: [OverpassElement], latitude: Double, longitude: Double) -> RoadSpeedLimitLookup {
        let candidates = elements.compactMap { element -> Candidate? in
            guard let tags = element.tags,
                  isLikelyDriveableRoad(tags),
                  let rawLimit = tags["maxspeed"],
                  let limitMPH = parseMaxspeed(rawLimit) else {
                return nil
            }

            let distance = distanceFromPoint(latitude: latitude, longitude: longitude, to: element.geometry)
            let roadName = tags["name"] ?? tags["ref"]
            return Candidate(limitMPH: limitMPH, roadName: roadName, distanceMeters: distance)
        }

        guard let best = candidates.sorted(by: { lhs, rhs in
            lhs.distanceMeters < rhs.distanceMeters
        }).first else {
            return RoadSpeedLimitLookup(limitMPH: nil, roadName: nil, sourceDescription: "Road speed limit not found")
        }

        let source = best.roadName.map { "OSM road limit on \($0)" } ?? "OSM road limit"
        return RoadSpeedLimitLookup(limitMPH: best.limitMPH, roadName: best.roadName, sourceDescription: source)
    }

    /*
     Purpose:
     Converts an OpenStreetMap maxspeed string into miles per hour.
    */
    private static func parseMaxspeed(_ value: String) -> Double? {
        // OSM maxspeed values may include units, or in the US they may be plain mph numbers.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard !lowercased.isEmpty,
              lowercased != "none",
              lowercased != "signals",
              lowercased != "walk" else {
            return nil
        }

        let normalized = lowercased.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
              let value = Double(normalized[range]) else {
            return nil
        }

        if normalized.contains("mph") {
            return value
        }
        if normalized.contains("knots") {
            return value * 1.150779
        }

        if Locale.current.region?.identifier == "US" {
            return value
        }
        return value * 0.621371
    }

    /*
     Purpose:
     Filters Overpass road candidates down to roads that should be usable by cars.
    */
    private static func isLikelyDriveableRoad(_ tags: [String: String]) -> Bool {
        guard let highway = tags["highway"] else { return false }
        let driveableHighways: Set<String> = [
            "motorway",
            "trunk",
            "primary",
            "secondary",
            "tertiary",
            "unclassified",
            "residential",
            "living_street",
            "service",
            "road",
            "motorway_link",
            "trunk_link",
            "primary_link",
            "secondary_link",
            "tertiary_link"
        ]
        guard driveableHighways.contains(highway) else { return false }
        if tags["access"] == "no" || tags["motor_vehicle"] == "no" || tags["vehicle"] == "no" {
            return false
        }
        return true
    }

    /*
     Purpose:
     Finds how close the current GPS coordinate is to a road geometry.
    */
    private static func distanceFromPoint(latitude: Double, longitude: Double, to geometry: [OverpassGeometryPoint]?) -> Double {
        guard let geometry, geometry.count > 1 else { return .greatestFiniteMagnitude }
        let projectedPoints = geometry.map { project(latitude: $0.lat, longitude: $0.lon, originLatitude: latitude, originLongitude: longitude) }
        var best = Double.greatestFiniteMagnitude

        for index in 0..<(projectedPoints.count - 1) {
            let start = projectedPoints[index]
            let end = projectedPoints[index + 1]
            best = min(best, distanceFromOrigin(toSegmentStart: start, end: end))
        }

        return best
    }

    /*
     Purpose:
     Computes the shortest projected distance from the current point to one road segment.
    */
    private static func distanceFromOrigin(toSegmentStart start: ProjectedPoint, end: ProjectedPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let segmentLengthSquared = dx * dx + dy * dy
        guard segmentLengthSquared > 0 else {
            return hypot(start.x, start.y)
        }

        let t = max(0, min(1, -(start.x * dx + start.y * dy) / segmentLengthSquared))
        let closestX = start.x + t * dx
        let closestY = start.y + t * dy
        return hypot(closestX, closestY)
    }

    /*
     Purpose:
     Projects latitude and longitude into local meters for simple distance math.
    */
    private static func project(latitude: Double, longitude: Double, originLatitude: Double, originLongitude: Double) -> ProjectedPoint {
        let earthRadiusMeters = 6_371_000.0
        let originLatitudeRadians = originLatitude * .pi / 180
        let x = (longitude - originLongitude) * .pi / 180 * cos(originLatitudeRadians) * earthRadiusMeters
        let y = (latitude - originLatitude) * .pi / 180 * earthRadiusMeters
        return ProjectedPoint(x: x, y: y)
    }

    /*
     Purpose:
     Calculates the approximate great-circle distance between two coordinates.
    */
    private static func distanceMeters(
        fromLatitude latitude: Double,
        longitude: Double,
        toLatitude otherLatitude: Double,
        longitude otherLongitude: Double
    ) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let latitudeDelta = (otherLatitude - latitude) * .pi / 180
        let longitudeDelta = (otherLongitude - longitude) * .pi / 180
        let startLatitude = latitude * .pi / 180
        let endLatitude = otherLatitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * earthRadiusMeters * atan2(sqrt(a), sqrt(1 - a))
    }

    /*
     Purpose:
     Encodes an Overpass query so it can be sent as POST form data.
    */
    private static func formEncoded(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

private struct CachedLookup {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var result: RoadSpeedLimitLookup
}

private struct Candidate {
    var limitMPH: Double
    var roadName: String?
    var distanceMeters: Double
}

private struct ProjectedPoint {
    var x: Double
    var y: Double
}

private struct OverpassResponse: Decodable, Sendable {
    var elements: [OverpassElement]
}

private struct OverpassElement: Decodable, Sendable {
    var tags: [String: String]?
    var geometry: [OverpassGeometryPoint]?
}

private struct OverpassGeometryPoint: Decodable, Sendable {
    var lat: Double
    var lon: Double
}
