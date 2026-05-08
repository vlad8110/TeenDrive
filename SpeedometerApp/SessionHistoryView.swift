import MapKit
import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        List {
            if store.sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "map", description: Text("Start tracking to save your first route."))
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
        .navigationTitle("Sessions")
    }
}

private struct SessionRow: View {
    let session: SpeedSession

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
        }
        .padding(.vertical, 4)
    }
}

private struct SessionDetailView: View {
    let session: SpeedSession
    @State private var position: MapCameraPosition

    init(session: SpeedSession) {
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
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    DetailMetric(title: "Distance", value: String(format: "%.2f mi", session.distanceMiles))
                    DetailMetric(title: "Top", value: String(format: "%.0f mph", session.topSpeedMPH))
                    DetailMetric(title: "Time", value: session.duration.durationText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.headline)
                    Text("Ended \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Route")
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
