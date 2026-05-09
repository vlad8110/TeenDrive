import MapKit
import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
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

                if session.coordinates.count > 1 {
                    MapPolyline(coordinates: session.coordinates)
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
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Trip Route")
        .navigationBarTitleDisplayMode(.inline)
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
