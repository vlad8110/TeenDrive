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
                            needsPermission: needsPermission,
                            onSelectTab: { selectedTeenTab = $0 }
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
        .background((selectedTeenTab == .drive || selectedTeenTab == .home) ? Color.black : Color(.systemGroupedBackground))
        .ignoresSafeArea((selectedTeenTab == .drive || selectedTeenTab == .home) ? .container : [], edges: .bottom)
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
    let onSelectTab: (TeenTab) -> Void

    @State private var isShowingScoreBreakdown = false

    private var safeScore: Int {
        sessionStore.sessions.first?.behaviorScoreBreakdown.score ?? 85
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

    private var averageScoreText: String {
        averageTripScore.map { "\($0)" } ?? "\(safeScore)"
    }

    private var greetingName: String {
        let trimmed = accountStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Teen" : trimmed
    }

    private var todaysDriveMinutes: Int {
        guard let latest = sessionStore.sessions.first else { return 0 }
        return max(0, Int(latest.duration / 60))
    }

    private var safeStreak: Int {
        let safeTrips = sessionStore.sessions.prefix { $0.behaviorScoreBreakdown.score >= 80 }
        return max(safeTrips.count, sessionStore.sessions.isEmpty ? 5 : 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                homeHeader(compact: compact)
                scoreHero(compact: compact)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: compact ? 7 : 9) {
                    homeStatTile(icon: "clock", color: .green, title: "Last Drive", value: "\(todaysDriveMinutes) min", detail: "Duration", compact: compact)
                    homeStatTile(icon: "car.fill", color: .blue, title: "Trips", value: "\(tripCount)", detail: "Total drives", compact: compact)
                    homeStatTile(icon: "star", color: .green, title: "Avg Score", value: averageScoreText, detail: "All trips", compact: compact)
                    homeStatTile(icon: "checkmark.shield", color: .green, title: "Safe Streak", value: "\(safeStreak)", detail: "Safe drives", compact: compact)
                }

                focusAndParentGrid(compact: compact)
                quickInsights(compact: compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, compact ? 50 : 60)
            .padding(.bottom, 6)
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
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

    private func homeHeader(compact: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text("TeenDrive")
                    .font(.system(size: compact ? 32 : 38, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Text("Good afternoon,")
                        .foregroundStyle(.white.opacity(0.58))
                    Text("\(greetingName)!")
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Text("Hi")
                        .foregroundStyle(.white.opacity(0.58))
                }
                .font(compact ? .subheadline : .headline)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: compact ? 10 : 12) {
                Image(systemName: "bell")
                    .font((compact ? Font.title3 : .title2).weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 44 : 52, height: compact ? 44 : 52)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .offset(x: -8, y: 8)
                    }

                Button {
                    onSelectTab(.profile)
                } label: {
                    Image(systemName: "person.fill")
                        .font((compact ? Font.title3 : .title2).weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: compact ? 44 : 52, height: compact ? 44 : 52)
                        .background(Color.white.opacity(0.1), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scoreHero(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text("Safe Driving Score")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))

                VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                    Text(scoreHeadline)
                        .font((compact ? Font.title3 : .title).bold())
                        .foregroundStyle(.green)
                    Text("You're driving safely and building great habits.")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(compact ? 1 : 2)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 9, height: 9)
                    Text(lastTrip == nil ? "Starter score" : "Last trip summary")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Spacer(minLength: 8)

            scoreRing
                .frame(width: compact ? 104 : 126, height: compact ? 104 : 126)
                .contentShape(Rectangle())
                .onTapGesture {
                    if lastTrip != nil {
                        isShowingScoreBreakdown = true
                    }
                }
        }
        .frame(minHeight: compact ? 124 : 148)
        .padding(compact ? 12 : 16)
        .background(homeCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 15)
            Circle()
                .trim(from: 0, to: CGFloat(safeScore) / 100)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(safeScore)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("/100")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func focusAndParentGrid(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text("Top Focus Area")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 8) {
                    Image(systemName: topIssueCard.primary == "None" ? "checkmark" : "exclamationmark")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                        .background(topIssueCard.primary == "None" ? Color.green : Color.orange, in: Circle())

                    Text(topIssueCard.primary)
                        .font((compact ? Font.headline : .title3).bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(topIssueCard.primary == "None" ? "Great driving! Keep up your safe habits." : topIssueCard.secondary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(compact ? 2 : 3)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 118 : 140, alignment: .topLeading)
            .padding(compact ? 10 : 12)
            .background(
                LinearGradient(colors: [Color.green.opacity(0.24), Color.white.opacity(0.07)], startPoint: .bottomTrailing, endPoint: .topLeading),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text("Parent Connection")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                        .background(Color.blue.opacity(0.18), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountStore.connectedParentName.isEmpty ? "Not connected" : "Connected")
                            .font((compact ? Font.subheadline : .headline).bold())
                            .foregroundStyle(.white)
                        Text(accountStore.connectedParentName.isEmpty ? "Pair with a parent to share your progress." : accountStore.connectedParentName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(compact ? 2 : 3)
                    }
                }

                if accountStore.connectedParentName.isEmpty {
                    Button {
                        onSelectTab(.profile)
                    } label: {
                        Text("Pair now")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 30 : 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 118 : 140, alignment: .topLeading)
            .padding(compact ? 10 : 12)
            .background(homeCardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private func quickInsights(compact: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                Label("Quick Insights", systemImage: "chart.xyaxis.line")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.blue, .white)

                insightRow("No harsh braking on your last 3 trips.", compact: compact)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("Best drive this week:")
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(max(safeScore, averageTripScore ?? safeScore))")
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }
                .font(compact ? .caption : .subheadline)
            }

            Spacer()

            Button {
                onSelectTab(.reports)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
                    .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: compact ? 76 : 92)
        .padding(compact ? 10 : 14)
        .background(homeCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var scoreHeadline: String {
        safeScore >= 85 ? "Great job!" : safeScore >= 70 ? "Good progress" : "Needs focus"
    }

    private var homeCardBackground: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.11), Color.white.opacity(0.055)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func homeStatTile(icon: String, color: Color, title: String, value: String, detail: String, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: icon)
                .font((compact ? Font.headline : .title3).weight(.semibold))
                .foregroundStyle(color)
                .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                .background(color.opacity(0.2), in: Circle())

            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                Text(title)
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
                Text(value)
                    .font((compact ? Font.subheadline : .headline).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 68 : 82, alignment: .leading)
        .padding(compact ? 9 : 12)
        .background(homeCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func insightRow(_ text: String, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(text)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .font(compact ? .caption : .subheadline)
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
