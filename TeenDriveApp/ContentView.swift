import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var accountStore: AccountStore
    @StateObject private var sessionStore: SessionStore
    @StateObject private var safetySettings: SafetyAlertSettings
    @StateObject private var tracker: TeenDriveTracker

    init() {
        let accountStore = AccountStore()
        let sessionStore = SessionStore()
        let safetySettings = SafetyAlertSettings()
        _accountStore = StateObject(wrappedValue: accountStore)
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _safetySettings = StateObject(wrappedValue: safetySettings)
        _tracker = StateObject(wrappedValue: TeenDriveTracker(sessionStore: sessionStore, safetySettings: safetySettings, accountStore: accountStore))
    }

    var body: some View {
        if accountStore.hasSelectedRole {
            NavigationStack {
                if accountStore.role == .teen {
                    teenDashboard
                } else {
                    ParentDashboardView(store: sessionStore, tracker: tracker, accountStore: accountStore)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                NavigationLink {
                                    AccountSettingsView(accountStore: accountStore)
                                } label: {
                                    Label("Account", systemImage: "person.crop.circle")
                                }

                                NavigationLink {
                                    SafetyAlertSettingsView(settings: safetySettings, tracker: tracker)
                                } label: {
                                    Label("Alerts", systemImage: "bell.badge")
                                }
                            }
                        }
                }
            }
            .task {
                sessionStore.configure(accountStore: accountStore)
            }
            .onChange(of: accountStore.connectedTeens) {
                sessionStore.bindRemoteTrips()
            }
        } else {
            RoleSelectionView(accountStore: accountStore)
        }
    }

    private var teenDashboard: some View {
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
                MetricTile(title: "Alerts", value: "\(tracker.currentTripAlertCount)")
            }

            Text(tracker.statusMessage)
                .font(.callout)
                .foregroundStyle(tracker.currentTripAlertCount > 0 && tracker.isTracking ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if tracker.isAutoStartArmed {
                Label("Teen driving auto-start at 5 mph", systemImage: "car.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            accountStatus

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
                Label(tracker.isTracking ? "End Drive" : "Start Drive", systemImage: tracker.isTracking ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tracker.isTracking ? .red : .green)
        }
        .padding(20)
        .navigationTitle("Teen Drive")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    AccountSettingsView(accountStore: accountStore)
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    SafetyAlertSettingsView(settings: safetySettings, tracker: tracker)
                } label: {
                    Label("Alerts", systemImage: "bell.badge")
                }

                NavigationLink {
                    SessionHistoryView(store: sessionStore)
                } label: {
                    Label("Trips", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var needsPermission: Bool {
        tracker.authorizationStatus == .notDetermined || tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
    }

    @ViewBuilder
    private var accountStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(accountStore.role == .teen ? "Teen Account" : "Parent Account", systemImage: accountStore.role == .teen ? "person.fill" : "person.2.fill")
                .font(.callout.weight(.semibold))

            if accountStore.role == .teen {
                if accountStore.connectedParentName.isEmpty {
                    Text(accountStore.firebaseStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connected parent: \(accountStore.connectedParentName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !accountStore.connectedTeens.isEmpty {
                Text("Connected teens: \(accountStore.connectedTeens.count) • \(accountStore.firebaseStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No teen connected. Open Account to scan QR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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
