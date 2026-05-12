/*
 File: ParentDashboardView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Displays parent account status, active teen drives, live maps, safety alert pins, and completed trip history.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import MapKit
import SwiftUI

struct ParentDashboardView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var accountStore: AccountStore
    @State private var selectedTeenFilterID = "all"

    private var visibleTripSummaries: [ParentTripSummary] {
        guard selectedTeenFilterID != "all" else { return store.parentTripSummaries }
        return store.parentTripSummaries.filter { $0.teenProfileID == selectedTeenFilterID }
    }

    private var visibleActiveDrives: [ActiveTeenDrive] {
        guard selectedTeenFilterID != "all" else { return store.activeTeenDrives }
        return store.activeTeenDrives.filter { $0.teenProfileID == selectedTeenFilterID }
    }

    private var cloudConnectedTeens: [ConnectedTeen] {
        accountStore.connectedTeens.filter { !$0.teenProfileID.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountSection
                teenFilterBar
                activeDriveSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("Teen Trips")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if visibleTripSummaries.isEmpty {
                        ContentUnavailableView("No Trips", systemImage: "car", description: Text("Completed drives will appear here."))
                            .padding(.vertical, 24)
                    } else {
                        ForEach(visibleTripSummaries) { summary in
                            NavigationLink {
                                SessionDetailView(session: summary.trip)
                            } label: {
                                ParentTripCard(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(GlassAppBackground())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Parent")
    }

    @ViewBuilder
    private var teenFilterBar: some View {
        if cloudConnectedTeens.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    teenFilterButton(title: "All", id: "all")
                    ForEach(cloudConnectedTeens) { teen in
                        teenFilterButton(title: teen.name, id: teen.teenProfileID)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /*
     Purpose:
     Builds a parent dashboard filter button for one teen or all teens.
    */
    private func teenFilterButton(title: String, id: String) -> some View {
        Button {
            selectedTeenFilterID = id
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTeenFilterID == id ? .white : .green)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedTeenFilterID == id ? Color.green.gradient : Color.clear.gradient, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(selectedTeenFilterID == id ? 0.18 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(accountStore.role == .parent ? "Parent Account" : "Teen Account", systemImage: "person.2.fill")
                .font(.headline)

            if accountStore.role == .parent {
                if accountStore.connectedTeens.isEmpty {
                    Text("Open Account to scan the teen pairing QR.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connected teens: \(accountStore.connectedTeens.map(\.name).joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !accountStore.hasConnectedParent {
                Text("No parent connected. Open Account to show the pairing QR.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connected parent: \(accountStore.connectedParentDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .teenGlassCard()
    }

    @ViewBuilder
    private var activeDriveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(visibleActiveDrives.isEmpty ? "No Active Drive" : "Live Teen Drive", systemImage: visibleActiveDrives.isEmpty ? "location.slash" : "location.fill")
                    .font(.headline)
                    .foregroundStyle(visibleActiveDrives.isEmpty ? Color.secondary : Color.green)
                Spacer()
                Text(visibleActiveDrives.isEmpty ? "Waiting" : "\(visibleActiveDrives.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if visibleActiveDrives.isEmpty {
                Text("Live location appears only while a connected teen is actively tracking and location permission allows updates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleActiveDrives) { drive in
                    ActiveTeenDriveCard(drive: drive)
                }
            }
        }
        .padding(16)
        .teenGlassCard()
    }
}

private struct ParentTripCard: View {
    let summary: ParentTripSummary

    private var session: TeenTrip {
        summary.trip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.teenName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text("Ended \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.safetyAlertCount > 0 {
                    Label("\(session.safetyAlertCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }

            TripPreviewMap(session: session)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                ParentMetric(title: "Distance", value: String(format: "%.2f mi", session.distanceMiles))
                ParentMetric(title: "Duration", value: session.duration.durationText)
                ParentMetric(title: "Top", value: String(format: "%.0f mph", session.topSpeedMPH))
            }

            SafetyAlertStrip(session: session)
        }
        .padding(14)
        .teenGlassCard()
    }
}

private struct ActiveTeenDriveCard: View {
    let drive: ActiveTeenDrive

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(drive.teenName)
                        .font(.headline)
                    Spacer()
                    Text("Updated \(drive.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ParentMetric(title: "Current", value: String(format: "%.0f mph", drive.speedMPH))
                    ParentMetric(title: "Top", value: String(format: "%.0f mph", drive.topSpeedMPH))
                    ParentMetric(title: "Duration", value: durationText(now: timeline.date))
                }

                ActiveDriveMap(drive: drive)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    ParentMetric(title: "Distance", value: String(format: "%.2f mi", drive.distanceMiles))
                    ParentMetric(title: "Alerts", value: "\(drive.alertCount)")
                    ParentMetric(title: "Started", value: drive.startedAt.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .padding(12)
        .teenGlassControl()
    }

    /*
     Purpose:
     Formats a live or completed drive duration for display.
    */
    private func durationText(now: Date) -> String {
        now.timeIntervalSince(drive.startedAt).durationText
    }
}

private struct ActiveDriveMap: View {
    let drive: ActiveTeenDrive

    private var coordinates: [CLLocationCoordinate2D] {
        drive.route.map(\.coordinate)
    }

    private var region: MKCoordinateRegion {
        let allCoordinates = coordinates
            + [drive.lastKnownLocation?.coordinate].compactMap { $0 }
            + drive.safetyAlerts.compactMap(\.coordinate)
        guard let first = allCoordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        let bounds = allCoordinates.reduce(
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

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((bounds.maxLat - bounds.minLat) * 1.5, 0.01),
                longitudeDelta: max((bounds.maxLon - bounds.minLon) * 1.5, 0.01)
            )
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 4)
            }

            if let first = drive.route.first {
                Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                    .tint(.green)
            }

            ForEach(drive.safetyAlerts) { alert in
                if let coordinate = alert.coordinate {
                    Marker(alert.kind.title, systemImage: alert.kind.systemImage, coordinate: coordinate)
                        .tint(.orange)
                }
            }

            if let point = drive.lastKnownLocation {
                Marker("Current", systemImage: "location.fill", coordinate: point.coordinate)
                    .tint(.green)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }
}

private struct TripPreviewMap: View {
    let session: TeenTrip

    var body: some View {
        Map(initialPosition: .region(session.mapRegion)) {
            if session.coordinates.count > 1 {
                MapPolyline(coordinates: session.coordinates)
                    .stroke(.green, lineWidth: 4)
            }

            if let first = session.route.first {
                Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                    .tint(.green)
            }

            if let last = session.route.last {
                Marker("End", systemImage: "stop.fill", coordinate: last.coordinate)
                    .tint(.red)
            }

            ForEach(session.displaySafetyAlerts) { alert in
                if let coordinate = alert.coordinate {
                    Marker(alert.displayText, systemImage: alert.kind.systemImage, coordinate: coordinate)
                        .tint(.orange)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }
}

private struct ParentMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
