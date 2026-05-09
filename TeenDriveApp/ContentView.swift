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
            if accountStore.role == .teen {
                teenTabs
                    .task {
                        sessionStore.configure(accountStore: accountStore)
                    }
                    .onChange(of: accountStore.connectedTeens) {
                        sessionStore.bindRemoteTrips()
                    }
            } else {
                parentTabs
                    .task {
                        sessionStore.configure(accountStore: accountStore)
                    }
                    .onChange(of: accountStore.connectedTeens) {
                        sessionStore.bindRemoteTrips()
                    }
            }
        } else {
            RoleSelectionView(accountStore: accountStore)
        }
    }

    private var teenTabs: some View {
        TabView {
            NavigationStack {
                TeenHomeView(
                    tracker: tracker,
                    accountStore: accountStore,
                    sessionStore: sessionStore,
                    needsPermission: needsPermission
                )
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                teenDriveView
            }
            .tabItem {
                Label("Drive", systemImage: "car.fill")
            }

            NavigationStack {
                SessionHistoryView(store: sessionStore)
            }
            .tabItem {
                Label("Reports", systemImage: "doc.text")
            }

            NavigationStack {
                AccountSettingsView(accountStore: accountStore)
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
        }
    }

    private var parentTabs: some View {
        TabView {
            NavigationStack {
                ParentDashboardView(store: sessionStore, tracker: tracker, accountStore: accountStore)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                SessionHistoryView(store: sessionStore)
            }
            .tabItem {
                Label("Trips", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                AccountSettingsView(accountStore: accountStore)
            }
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
    }

    private var teenDriveView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(String(format: "%.0f", tracker.speedMPH))
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("mph")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MetricTile(title: "Top", value: String(format: "%.0f mph", tracker.topSpeedMPH))
                MetricTile(title: "Distance", value: String(format: "%.2f mi", tracker.distanceMiles))
                MetricTile(title: "Alerts", value: "\(tracker.currentTripAlertCount)")
            }

            Text(tracker.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if needsPermission {
                Button {
                    tracker.requestPermission()
                } label: {
                    Label("Allow Location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                tracker.isTracking ? tracker.stop() : tracker.start()
            } label: {
                Label(tracker.isTracking ? "End Drive" : "Start Drive", systemImage: tracker.isTracking ? "stop.fill" : "car.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isTracking ? .red : .blue)
            .controlSize(.large)
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Drive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SafetyAlertSettingsView(settings: safetySettings, tracker: tracker)
                } label: {
                    Image(systemName: "bell")
                }
            }
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

private struct TeenHomeView: View {
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var sessionStore: SessionStore
    let needsPermission: Bool

    private var safeScore: Int {
        let speedPenalty = max(0, Int(tracker.topSpeedMPH - 75))
        let alertPenalty = tracker.currentTripAlertCount * 5
        return max(0, min(100, 100 - speedPenalty - alertPenalty))
    }

    private var greetingName: String {
        let trimmed = accountStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Driver" : trimmed
    }

    private var todaysDriveMinutes: Int {
        guard let latest = sessionStore.sessions.first else { return 0 }
        return max(0, Int(latest.duration / 60))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                scoreRing

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(title: "Last Drive", primary: "\(todaysDriveMinutes)", secondary: "min")
                    statCard(title: "Top Issue", primary: tracker.currentTripAlertCount == 0 ? "None" : "Safety Alerts", secondary: tracker.currentTripAlertCount == 0 ? "Great driving" : "\(tracker.currentTripAlertCount) this drive")
                    statCard(title: "Streak", primary: safeScore >= 80 ? "5" : "1", secondary: "safe drives")
                    statCard(title: "Parent Status", primary: accountStore.connectedParentName.isEmpty ? "Not Connected" : "Connected", secondary: accountStore.connectedParentName.isEmpty ? "Open Profile to pair" : accountStore.connectedParentName)
                }

                if needsPermission {
                    Button {
                        tracker.requestPermission()
                    } label: {
                        Label("Allow Location", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    tracker.isTracking ? tracker.stop() : tracker.start()
                } label: {
                    Label(tracker.isTracking ? "End Drive" : "Start Drive", systemImage: tracker.isTracking ? "stop.fill" : "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tracker.isTracking ? .red : .blue)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("TeenDrive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "bell")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Good afternoon,")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(greetingName)! 👋")
                    .font(.title2.bold())
            }
            Spacer()
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(.blue)
                )
        }
    }

    private var scoreRing: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: CGFloat(safeScore) / 100)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(safeScore)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Safe Score")
                        .font(.headline)
                }
            }
            .frame(width: 220, height: 220)
            Text(safeScore >= 80 ? "Great job!" : "Keep improving")
                .font(.headline)
                .foregroundStyle(safeScore >= 80 ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func statCard(title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(primary)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
