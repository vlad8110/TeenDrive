import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var accountStore: AccountStore
    @StateObject private var sessionStore: SessionStore
    @StateObject private var safetySettings: SafetyAlertSettings
    @StateObject private var tracker: TeenDriveTracker
    @State private var selectedTeenTab: TeenTab = .drive

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
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTeenTab {
                case .home:
                    NavigationStack {
                TeenHomeView(
                    tracker: tracker,
                    accountStore: accountStore,
                    sessionStore: sessionStore,
                    needsPermission: needsPermission
                )
                    }
                case .drive:
                    NavigationStack {
                        teenDriveView
                    }
                case .reports:
                    NavigationStack {
                        SessionHistoryView(store: sessionStore)
                    }
                case .profile:
                    NavigationStack {
                        AccountSettingsView(accountStore: accountStore)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 98)

            TeenTabBar(selectedTab: $selectedTeenTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(selectedTeenTab == .drive ? Color.black : Color(.systemGroupedBackground))
        .ignoresSafeArea(selectedTeenTab == .drive ? .container : [], edges: .bottom)
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
        TeenDriveDashboardView(
            tracker: tracker,
            sessionStore: sessionStore,
            needsPermission: needsPermission,
            onRequestPermission: {
                tracker.requestPermission()
            },
            onCenterMap: {
                tracker.centerMapOnCurrentLocation()
            },
            onToggleDrive: {
                tracker.isTracking ? tracker.stop() : tracker.start()
            },
            safetySettings: {
                SafetyAlertSettingsView(settings: safetySettings, tracker: tracker)
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private var needsPermission: Bool {
        tracker.authorizationStatus == .notDetermined || tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
    }

}

private enum TeenTab: String, CaseIterable, Identifiable {
    case home
    case drive
    case reports
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .drive:
            return "Drive"
        case .reports:
            return "Reports"
        case .profile:
            return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .drive:
            return "car.fill"
        case .reports:
            return "doc.text.fill"
        case .profile:
            return "person.fill"
        }
    }
}

private struct TeenTabBar: View {
    @Binding var selectedTab: TeenTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TeenTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.blue : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
    }
}

private struct TeenDriveDashboardView<Settings: View>: View {
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var sessionStore: SessionStore
    let needsPermission: Bool
    let onRequestPermission: () -> Void
    let onCenterMap: () -> Void
    let onToggleDrive: () -> Void
    @ViewBuilder let safetySettings: () -> Settings
    @State private var mapStyle: TeenDriveMapStyle = .standard

    private var latestScore: Int {
        sessionStore.sessions.first?.behaviorScoreBreakdown.score ?? 92
    }

    private var scoreLabel: String {
        latestScore >= 85 ? "Great" : latestScore >= 70 ? "Good" : "Review"
    }

    private func durationText(now: Date = Date()) -> String {
        guard let startedAt = tracker.activeTripStartedAt else { return "00:00:00" }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    var body: some View {
        Group {
            if tracker.isTracking {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    driveContent(duration: durationText(now: timeline.date))
                }
            } else {
                driveContent(duration: durationText())
            }
        }
        .background(Color.black)
    }

    private func driveContent(duration: String) -> some View {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    mapCard
                    metricsCard(duration: duration)
                    actionButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 74)
                .padding(.bottom, 18)
            }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drive")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Circle()
                        .fill(tracker.isTracking ? Color.green : Color.gray)
                        .frame(width: 9, height: 9)
                    Text(tracker.isTracking ? "Live drive in progress" : "Ready to drive")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tracker.isTracking ? Color.green : Color.white.opacity(0.62))
                }
            }

            Spacer()

            NavigationLink {
                safetySettings()
            } label: {
                Image(systemName: "bell")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
        }
    }

    private var mapCard: some View {
        ZStack(alignment: .leading) {
            TeenLiveDriveMap(route: tracker.currentRoute, lastKnownLocation: tracker.lastKnownLocation)
                .environment(\.teenDriveMapStyle, mapStyle)
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(Color.blue.opacity(0.12))

            VStack(spacing: 8) {
                SpeedLimitBadge()
                Text(String(format: "%.0f", tracker.speedMPH))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                Text("mph")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(width: 86, height: 144)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
            .padding(.leading, 18)

            VStack(spacing: 18) {
                Spacer()
                Button(action: onCenterMap) {
                    Image(systemName: "location.circle.fill")
                }
                .buttonStyle(.plain)
                Button {
                    mapStyle.toggle()
                } label: {
                    Image(systemName: "square.3.layers.3d.down.right")
                }
                .buttonStyle(.plain)
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 18)
            .padding(.bottom, 28)
        }
    }

    private func metricsCard(duration: String) -> some View {
        HStack(spacing: 0) {
            DriveMetric(
                icon: "checkmark.shield.fill",
                iconColor: .green,
                title: "Safety Score",
                value: "\(latestScore)",
                detail: scoreLabel
            )

            Divider().background(Color.white.opacity(0.16))

            DriveMetric(
                icon: "road.lanes",
                iconColor: .white.opacity(0.22),
                title: "Distance",
                value: String(format: "%.2f mi", tracker.distanceMiles),
                detail: nil
            )

            Divider().background(Color.white.opacity(0.16))

            DriveMetric(
                icon: "clock",
                iconColor: .white.opacity(0.22),
                title: "Duration",
                value: duration,
                detail: nil
            )
        }
        .frame(height: 112)
        .padding(.horizontal, 14)
        .background(darkCardBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButton: some View {
        VStack(spacing: 10) {
            if needsPermission {
                Button(action: onRequestPermission) {
                    Label("Allow Location", systemImage: "location.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.green, in: Capsule())
            }

            Button(action: onToggleDrive) {
                Label(tracker.isTracking ? "End Drive" : "Start Drive", systemImage: "car.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(tracker.isTracking ? Color.blue : Color.green, in: Capsule())
        }
    }

    private var darkCardBackground: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.12), Color.white.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum TeenDriveMapStyle {
    case standard
    case satellite

    mutating func toggle() {
        self = self == .standard ? .satellite : .standard
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .flat)
        case .satellite:
            return .hybrid(elevation: .flat)
        }
    }
}

private struct TeenDriveMapStyleKey: EnvironmentKey {
    static let defaultValue: TeenDriveMapStyle = .standard
}

private extension EnvironmentValues {
    var teenDriveMapStyle: TeenDriveMapStyle {
        get { self[TeenDriveMapStyleKey.self] }
        set { self[TeenDriveMapStyleKey.self] = newValue }
    }
}

private struct TeenLiveDriveMap: View {
    let route: [RoutePoint]
    let lastKnownLocation: RoutePoint?
    @Environment(\.teenDriveMapStyle) private var mapStyle
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static var fallbackCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    }

    private static var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: fallbackCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))
    }

    private var mapRegion: MKCoordinateRegion {
        guard let first = route.first?.coordinate ?? lastKnownLocation?.coordinate else {
            return Self.defaultRegion
        }

        let coordinates = route.map(\.coordinate)
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(center: first, span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025))
        }

        let bounds = coordinates.reduce(
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
                latitudeDelta: max((bounds.maxLat - bounds.minLat) * 1.7, 0.018),
                longitudeDelta: max((bounds.maxLon - bounds.minLon) * 1.7, 0.018)
            )
        )
    }

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if route.count > 1 {
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(.blue.opacity(0.35), lineWidth: 10)
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(.blue, lineWidth: 5)
            }

            if let first = route.first {
                Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                    .tint(.green)
            }

            if let lastKnownLocation {
                Annotation("Current", coordinate: lastKnownLocation.coordinate) {
                    CurrentLocationDot()
                }
            }
        }
        .mapStyle(mapStyle.mapStyle)
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapScaleView()
            MapUserLocationButton()
        }
        .onAppear {
            updateCamera(animated: false)
        }
        .onChange(of: route) {
            updateCamera(animated: true)
        }
        .onChange(of: lastKnownLocation) {
            updateCamera(animated: true)
        }
    }

    private func updateCamera(animated: Bool) {
        let position = MapCameraPosition.region(mapRegion)
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = position
            }
        } else {
            cameraPosition = position
        }
    }
}

private struct CurrentLocationDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.22))
                .frame(width: 54, height: 54)
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 31, height: 31)
            Circle()
                .fill(Color.blue)
                .frame(width: 21, height: 21)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

private struct SpeedLimitBadge: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("SPEED")
            Text("LIMIT")
            Text("35")
                .font(.system(size: 22, weight: .black))
        }
        .font(.system(size: 8, weight: .black))
        .foregroundStyle(.black)
        .frame(width: 42, height: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct DriveMetric: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(title == "Safety Score" ? Color.green : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct TeenHomeView: View {
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var sessionStore: SessionStore
    let needsPermission: Bool

    @State private var isShowingScoreBreakdown = false

    /// Safe score for the most recently completed trip (sessions are newest-first).
    private var lastDriveScore: Int? {
        sessionStore.sessions.first.map(\.behaviorScoreBreakdown.score)
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
        let total = sessionStore.sessions.reduce(0) { $0 + $1.behaviorScoreBreakdown.score }
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if lastTrip != nil {
                            isShowingScoreBreakdown = true
                        }
                    }

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
        .sheet(isPresented: $isShowingScoreBreakdown) {
            NavigationStack {
                if let trip = lastTrip {
                    ScoreBreakdownSheet(trip: trip)
                } else {
                    ContentUnavailableView("No trip", systemImage: "car", description: Text("Complete a drive first."))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingScoreBreakdown = false }
                            }
                        }
                }
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
            VStack(spacing: 4) {
                Text(lastDriveScore == nil ? "Complete a drive to see your score" : (praise ? "Great job!" : "Keep improving"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lastDriveScore == nil ? Color.secondary : (praise ? Color.green : Color.orange))
                    .multilineTextAlignment(.center)
                if lastDriveScore != nil {
                    Text("Tap score for details")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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

private struct ScoreBreakdownSheet: View {
    let trip: TeenTrip
    @Environment(\.dismiss) private var dismiss

    private var breakdown: TripBehaviorScoreBreakdown {
        trip.behaviorScoreBreakdown
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Trip score")
                        .font(.headline)
                    Spacer()
                    Text("\(breakdown.score)")
                        .font(.title.bold())
                        .monospacedDigit()
                }
                Text("Starts at 100. Each category subtracts points (capped) based on how you drove on this trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("What lowered your score") {
                breakdownRow(title: "Top speed over 75 mph", points: breakdown.topSpeedPenalty, detail: String(format: "Peak %.0f mph", trip.topSpeedMPH))
                breakdownRow(title: "Speeding alerts", points: breakdown.speedingPenalty, detail: "\(trip.speedLimitAlertCount) event\(trip.speedLimitAlertCount == 1 ? "" : "s")")
                breakdownRow(title: "Hard driving events", points: breakdown.drivingEventPenalty, detail: "\(trip.drivingEventAlertCount) event\(trip.drivingEventAlertCount == 1 ? "" : "s")")
                breakdownRow(title: "Harsh stops", points: breakdown.harshStopPenalty, detail: "\(trip.harshStopAlertCount) stop\(trip.harshStopAlertCount == 1 ? "" : "s")")
                breakdownRow(
                    title: "Overall alert rate",
                    points: breakdown.alertRatePenalty,
                    detail: String(
                        format: "%.1f alerts / hr (est.)",
                        Double(trip.safetyAlertCount) / max(trip.duration / 3600, 0.1667)
                    )
                )
            }

            Section {
                HStack {
                    Text("Total deductions")
                    Spacer()
                    Text(String(format: "−%.0f", breakdown.totalPenalty))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("Why this score?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func breakdownRow(title: String, points: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "−%.0f", points))
                    .foregroundStyle(points > 0.5 ? .orange : .secondary)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
