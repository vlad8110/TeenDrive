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
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                                    .padding(12)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
            .padding(.bottom, 4)
        }
        .background(Color.black)
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
