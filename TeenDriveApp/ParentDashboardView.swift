import MapKit
import SwiftUI

struct ParentDashboardView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var accountStore: AccountStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountSection
                activeDriveSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("Teen Trips")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if store.sessions.isEmpty {
                        ContentUnavailableView("No Trips", systemImage: "car", description: Text("Completed drives will appear here."))
                            .padding(.vertical, 24)
                    } else {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                ParentTripCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Parent")
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
            } else if accountStore.connectedParentName.isEmpty {
                Text("No parent connected. Open Account to show the pairing QR.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connected parent: \(accountStore.connectedParentName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var activeDriveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tracker.isTracking ? "Drive Active" : "No Active Drive", systemImage: tracker.isTracking ? "location.fill" : "location.slash")
                    .font(.headline)
                    .foregroundStyle(tracker.isTracking ? .green : .secondary)
                Spacer()
                Text(tracker.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if tracker.isTracking {
                HStack(spacing: 12) {
                    ParentMetric(title: "Current", value: String(format: "%.0f mph", tracker.speedMPH))
                    ParentMetric(title: "Top", value: String(format: "%.0f mph", tracker.topSpeedMPH))
                    ParentMetric(title: "Alerts", value: "\(tracker.currentTripAlertCount)")
                }

                if let startedAt = tracker.activeTripStartedAt {
                    Text("Started \(startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let point = tracker.lastKnownLocation {
                    LastKnownLocationMap(point: point)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Last known \(point.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Last known location appears only while the teen drive is actively tracking and location permission allows updates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ParentTripCard: View {
    let session: TeenTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LastKnownLocationMap: View {
    let point: RoutePoint

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: point.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        ) {
            Marker("Last Known", systemImage: "location.fill", coordinate: point.coordinate)
                .tint(.green)
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
