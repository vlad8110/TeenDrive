/*
 File: SessionHistoryView.swift
 Created: 2026-05-08
 Creator: Vladimyr Merci

 Purpose:
 Shows saved trips, trip details, route maps, safety alerts, and score breakdowns.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import MapKit
import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var store: SessionStore
    var usesTeenHeader = false

    var body: some View {
        if usesTeenHeader {
            teenHistoryBody
        } else {
            standardHistoryBody
        }
    }

    private var standardHistoryBody: some View {
        List {
            if store.sessions.isEmpty {
                ContentUnavailableView("No Trips", systemImage: "car", description: Text("Start a drive to save the first route."))
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
                .onDelete(perform: store.delete)
            }
        }
        .navigationTitle("Trip History")
        .scrollContentBackground(.hidden)
        .background(GlassAppBackground())
        .environment(\.colorScheme, .dark)
    }

    private var teenHistoryBody: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                TeenScreenHeader(title: "Reports", compact: compact) {
                    Text(store.sessions.isEmpty ? "No trips yet" : "\(store.sessions.count) saved trip\(store.sessions.count == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.62))
                } actions: {
                    EmptyView()
                }

                if store.sessions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "car")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("No Trips")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        Text("Start a drive to save the first route.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .teenGlassCard()
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                                    .padding(12)
                                    .teenGlassCard()
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: store.delete)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, compact ? 22 : 34)
            .padding(.bottom, compact ? 16 : 20)
        }
        .background(GlassAppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SessionRow: View {
    let session: TeenTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                Label(String(format: "%.2f mi", session.distanceMiles), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(session.duration.durationText, systemImage: "timer")
                Label(String(format: "%.0f mph", session.topSpeedMPH), systemImage: "speedometer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if session.safetyAlertCount > 0 {
                Label("\(session.safetyAlertCount) safety alert\(session.safetyAlertCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            SafetyAlertStrip(session: session)
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    let session: TeenTrip
    @State private var position: MapCameraPosition
    @State private var roadMatchedCoordinates: [CLLocationCoordinate2D] = []

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
    init(session: TeenTrip) {
        self.session = session
        _position = State(initialValue: .region(session.mapRegion))
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                if let first = session.route.first {
                    Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                        .tint(.green)
                }

                if let last = session.route.last {
                    Marker("End", systemImage: "stop.fill", coordinate: last.coordinate)
                        .tint(.red)
                }

                let displayCoordinates = roadMatchedCoordinates.isEmpty ? session.coordinates : roadMatchedCoordinates
                if displayCoordinates.count > 1 {
                    MapPolyline(coordinates: displayCoordinates)
                        .stroke(.green, lineWidth: 5)
                }

                ForEach(session.displaySafetyAlerts) { alert in
                    if let coordinate = alert.coordinate {
                        Marker(alert.displayText, systemImage: alert.kind.systemImage, coordinate: coordinate)
                            .tint(.orange)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    DetailMetric(title: "Distance", value: String(format: "%.2f mi", session.distanceMiles))
                    DetailMetric(title: "Top", value: String(format: "%.0f mph", session.topSpeedMPH))
                    DetailMetric(title: "Alerts", value: "\(session.safetyAlertCount)")
                }

                SafetyAlertStrip(session: session)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.headline)
                    Text("Ended \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !session.displaySafetyAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Safety Alerts")
                            .font(.headline)
                        ForEach(session.displaySafetyAlerts) { alert in
                            HStack {
                                Label(alert.kind.title, systemImage: alert.kind.systemImage)
                                    .foregroundStyle(.orange)
                                Text(alert.displayText)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
            }
        }
        .navigationTitle("Trip Route")
        .navigationBarTitleDisplayMode(.inline)
        .background(GlassAppBackground())
        .environment(\.colorScheme, .dark)
        .task(id: session.id) {
            roadMatchedCoordinates = await RoadMatchedRouteBuilder.coordinates(for: session.route)
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum RoadMatchedRouteBuilder {
    /*
     Purpose:
     Builds a road-following display polyline for completed reports.

     The trip still stores the actual GPS samples. This display helper asks Apple Maps for automobile
     directions between representative route points so sparse background samples do not appear as long
     straight lines across neighborhoods. If directions fail or the network is unavailable, callers fall
     back to the raw GPS polyline.
    */
    static func coordinates(for route: [RoutePoint]) async -> [CLLocationCoordinate2D] {
        let anchors = sampledAnchors(from: route)
        guard anchors.count > 1 else { return [] }

        var matchedCoordinates: [CLLocationCoordinate2D] = []
        for index in anchors.indices.dropLast() {
            guard let legCoordinates = await directionsCoordinates(from: anchors[index], to: anchors[index + 1]),
                  legCoordinates.count > 1 else {
                continue
            }

            if matchedCoordinates.isEmpty {
                matchedCoordinates.append(contentsOf: legCoordinates)
            } else {
                matchedCoordinates.append(contentsOf: legCoordinates.dropFirst())
            }
        }

        return matchedCoordinates.count > 1 ? matchedCoordinates : []
    }

    /*
     Purpose:
     Chooses enough route points to preserve the trip shape without making too many directions requests.
    */
    private static func sampledAnchors(from route: [RoutePoint]) -> [CLLocationCoordinate2D] {
        let coordinates = route.map(\.coordinate)
        guard coordinates.count > 12 else { return coordinates }

        let step = max(1, coordinates.count / 10)
        var anchors = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }
        if let lastAnchor = anchors.last,
           let lastCoordinate = coordinates.last,
           lastAnchor.latitude != lastCoordinate.latitude || lastAnchor.longitude != lastCoordinate.longitude {
            anchors.append(lastCoordinate)
        }
        return anchors
    }

    /*
     Purpose:
     Requests one automobile route leg from Apple Maps.
    */
    private static func directionsCoordinates(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.first?.polyline.coordinates
        } catch {
            return nil
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}
