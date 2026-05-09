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

    private func tripSafeScore(_ trip: TeenTrip) -> Int {
        let durationHours = max(trip.duration / 3600, 0.1667) // 10-minute floor avoids inflated short-trip rates.
        let totalAlerts = Double(trip.safetyAlertCount)

        let topSpeedPenalty = min(15, max(0, (trip.topSpeedMPH - 75) * 0.8))
        let speedingPenalty = min(30, Double(trip.speedLimitAlertCount) * 5)
        let drivingEventPenalty = min(28, Double(trip.drivingEventAlertCount) * 7)
        let harshStopPenalty = min(12, Double(trip.harshStopAlertCount) * 4)
        let alertRatePenalty = min(15, (totalAlerts / durationHours) * 1.8)

        let penalty = topSpeedPenalty + speedingPenalty + drivingEventPenalty + harshStopPenalty + alertRatePenalty
        return max(0, min(100, Int((100 - penalty).rounded())))
    }

    /// Safe score for the most recently completed trip (sessions are newest-first).
    private var lastDriveScore: Int? {
        sessionStore.sessions.first.map { tripSafeScore($0) }
    }

    private var lastTrip: TeenTrip? {
        sessionStore.sessions.first
    }

    private var topIssueCard: (primary: String, secondary: String) {
        guard let trip = lastTrip else { return ("None", "No trips yet") }

        if trip.speedLimitAlertCount >= max(trip.drivingEventAlertCount, trip.harshStopAlertCount), trip.speedLimitAlertCount > 0 {
            return ("Speeding", "\(trip.speedLimitAlertCount) event\(trip.speedLimitAlertCount == 1 ? "" : "s")")
        }
        if trip.drivingEventAlertCount > 0 {
            return ("Hard Events", "\(trip.drivingEventAlertCount) event\(trip.drivingEventAlertCount == 1 ? "" : "s")")
        }
        if trip.harshStopAlertCount > 0 {
            return ("Harsh Stops", "\(trip.harshStopAlertCount) stop\(trip.harshStopAlertCount == 1 ? "" : "s")")
        }
        return ("None", "Great driving")
    }

    private var tripCount: Int {
        sessionStore.sessions.count
    }

    private var averageTripScore: Int? {
        guard !sessionStore.sessions.isEmpty else { return nil }
        let total = sessionStore.sessions.reduce(0) { $0 + tripSafeScore($1) }
        return Int((Double(total) / Double(sessionStore.sessions.count)).rounded())
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
        GeometryReader { proxy in
            let compact = proxy.size.height < 780

            VStack(spacing: compact ? 10 : 14) {
                header
                scoreRing(diameter: compact ? 160 : 195, lastDriveScore: lastDriveScore, compact: compact)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: compact ? 8 : 10) {
                    statCard(title: "Last Drive", primary: "\(todaysDriveMinutes)", secondary: "min", compact: compact)
                    statCard(title: "Top Issue", primary: topIssueCard.primary, secondary: topIssueCard.secondary, compact: compact)
                    statCard(title: "Trips", primary: "\(tripCount)", secondary: "total drives", compact: compact)
                    statCard(title: "Avg Trip Score", primary: averageTripScore.map { "\($0)" } ?? "—", secondary: tripCount == 0 ? "No history yet" : "all trips", compact: compact)
                    statCard(title: "Streak", primary: (lastDriveScore ?? 0) >= 80 ? "5" : "1", secondary: "safe drives", compact: compact)
                    statCard(title: "Parent Status", primary: accountStore.connectedParentName.isEmpty ? "Not Connected" : "Connected", secondary: accountStore.connectedParentName.isEmpty ? "Open Profile to pair" : accountStore.connectedParentName, compact: compact)
                }

                Spacer(minLength: compact ? 4 : 10)

                if needsPermission {
                    Button {
                        tracker.requestPermission()
                    } label: {
                        Label("Allow Location", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.top, compact ? 8 : 12)
            .padding(.bottom, compact ? 8 : 12)
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

    private func scoreRing(diameter: CGFloat, lastDriveScore: Int?, compact: Bool) -> some View {
        let ringProgress = lastDriveScore.map { CGFloat($0) / 100 } ?? 0
        let praise = (lastDriveScore ?? 0) >= 80

        return VStack(spacing: compact ? 4 : 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: compact ? 12 : 14)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: compact ? 12 : 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(lastDriveScore.map { "\($0)" } ?? "—")
                        .font(.system(size: compact ? 44 : 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Last drive")
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(lastDriveScore == nil ? "Complete a drive to see your score" : (praise ? "Great job!" : "Keep improving"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(lastDriveScore == nil ? Color.secondary : (praise ? Color.green : Color.orange))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 4 : 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func statCard(title: String, primary: String, secondary: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(primary)
                .font((compact ? Font.title3 : .title2).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 68 : 82, alignment: .leading)
        .padding(compact ? 8 : 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
