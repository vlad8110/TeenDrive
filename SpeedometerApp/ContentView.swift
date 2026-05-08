import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var sessionStore: SessionStore
    @StateObject private var tracker: SpeedTracker

    init() {
        let sessionStore = SessionStore()
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _tracker = StateObject(wrappedValue: SpeedTracker(sessionStore: sessionStore))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(String(format: "%.0f", tracker.speedMPH))
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)

                    Text("mph")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

                HStack(spacing: 12) {
                    MetricTile(title: "Top", value: String(format: "%.0f mph", tracker.topSpeedMPH))
                    MetricTile(title: "Distance", value: String(format: "%.2f mi", tracker.distanceMiles))
                }

                Text(tracker.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if tracker.isAutoStartArmed {
                    Label("Auto-start at 5 mph", systemImage: "figure.walk.motion")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                if needsPermission {
                    Button {
                        tracker.requestPermission()
                    } label: {
                        Label("Allow Location", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    tracker.isTracking ? tracker.stop() : tracker.start()
                } label: {
                    Label(tracker.isTracking ? "Stop Tracking" : "Start Tracking", systemImage: tracker.isTracking ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(tracker.isTracking ? .red : .green)
            }
            .padding(20)
            .navigationTitle("Speedometer")
            .toolbar {
                NavigationLink {
                    SessionHistoryView(store: sessionStore)
                } label: {
                    Label("Sessions", systemImage: "clock.arrow.circlepath")
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var needsPermission: Bool {
        tracker.authorizationStatus == .notDetermined || tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
