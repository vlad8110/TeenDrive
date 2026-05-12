/*
 File: ContentView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Composes the main app shell, role routing, teen tabs, parent tabs, live maps, dashboard cards, and shared UI pieces.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import CoreLocation
import MapKit
import SwiftUI
import UIKit

// Owns the long-lived app stores so the tracker, account, settings, and trips stay in sync.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var accountStore: AccountStore
    @StateObject private var sessionStore: SessionStore
    @StateObject private var safetySettings: SafetyAlertSettings
    @StateObject private var tracker: TeenDriveTracker
    @State private var selectedTeenTab: TeenTab = .drive

    /*
     Purpose:
     Initializes this type with the state or dependencies needed before it is used.
    */
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
        Group {
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
        .tint(.green)
        .onChange(of: scenePhase) {
            // Opening the app during a drive is treated as a lightweight phone-use signal.
            if scenePhase == .active {
                tracker.recordPhoneUseIfDriving()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .teenDriveProtectedDataDidBecomeAvailable)) { _ in
            // Protected data becoming available is a practical signal that the phone was unlocked.
            tracker.recordPhoneUseIfDriving(reason: "Phone unlocked while moving")
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
                        SessionHistoryView(
                            store: sessionStore,
                            usesTeenHeader: true
                        )
                    }
                case .profile:
                    NavigationStack {
                        AccountSettingsView(accountStore: accountStore, usesTeenHeader: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 98)

            TeenTabBar(selectedTab: $selectedTeenTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(GlassAppBackground())
        .ignoresSafeArea(.container, edges: .bottom)
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
        .tint(.green)
        .background(GlassAppBackground())
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
            speedLimitMPH: safetySettings.speedLimitMPH,
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
                    .foregroundStyle(selectedTab == tab ? Color.green : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.24),
                                                    Color.green.opacity(0.1),
                                                    Color.white.opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .allowsHitTesting(false)
                                }
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                        .allowsHitTesting(false)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .shadow(color: Color.green.opacity(0.16), radius: 10, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .background {
            Capsule()
                .fill(Color.white.opacity(0.04))
                .blur(radius: 8)
        }
        .overlay(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.42), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.48), radius: 28, y: 12)
        .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
    }
}

struct TeenScreenHeader<Subtitle: View, Actions: View>: View {
    let title: String
    let compact: Bool
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                Text(title)
                    .font(.system(size: compact ? 31 : 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                subtitle()
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: compact ? 10 : 12) {
                actions()
            }
        }
        .frame(height: compact ? 52 : 62, alignment: .top)
    }
}

struct TeenHeaderCircleIcon: View {
    let systemName: String
    var color: Color = .white
    let compact: Bool
    var showsBadge = false

    var body: some View {
        Image(systemName: systemName)
            .font((compact ? Font.title3 : .title2).weight(.medium))
            .foregroundStyle(color)
            .frame(width: compact ? 42 : 48, height: compact ? 42 : 48)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().fill(Color.white.opacity(0.08)))
            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .offset(x: -7, y: 7)
                }
            }
    }
}

private struct TeenDriveDashboardView<Settings: View>: View {
    @ObservedObject var tracker: TeenDriveTracker
    @ObservedObject var sessionStore: SessionStore
    @Environment(\.openURL) private var openURL
    let needsPermission: Bool
    let onRequestPermission: () -> Void
    let onCenterMap: () -> Void
    let onToggleDrive: () -> Void
    let speedLimitMPH: Double
    @ViewBuilder let safetySettings: () -> Settings
    @State private var mapStyle: TeenDriveMapStyle = .standard

    private var latestScore: Int {
        sessionStore.sessions.first?.behaviorScoreBreakdown.score ?? 92
    }

    private var scoreLabel: String {
        latestScore >= 85 ? "Great" : latestScore >= 70 ? "Good" : "Review"
    }

    private var showsLocationPermissionAction: Bool {
        switch tracker.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse, .denied, .restricted:
            return true
        case .authorizedAlways:
            return false
        @unknown default:
            return true
        }
    }

    private var locationPermissionTitle: String {
        switch tracker.authorizationStatus {
        case .notDetermined:
            return "Allow Location"
        case .authorizedWhenInUse:
            return "Enable Always Location"
        case .denied, .restricted:
            return "Open Location Settings"
        case .authorizedAlways:
            return "Location Ready"
        @unknown default:
            return "Allow Location"
        }
    }

    private var locationPermissionIcon: String {
        switch tracker.authorizationStatus {
        case .authorizedWhenInUse:
            return "location.circle.fill"
        case .denied, .restricted:
            return "gearshape.fill"
        default:
            return "location.fill"
        }
    }

    private var locationPermissionColor: Color {
        switch tracker.authorizationStatus {
        case .authorizedWhenInUse:
            return .green
        case .denied, .restricted:
            return .orange
        default:
            return .green
        }
    }

    /*
     Purpose:
     Formats a live or completed drive duration for display.
    */
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
        .background(GlassAppBackground())
    }

    /*
     Purpose:
     Builds the main teen drive screen contents for the current layout size.
    */
    private func driveContent(duration: String) -> some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760
            let topPadding = driveTopPadding(compact: compact)
            let bottomPadding = compact ? CGFloat(16) : CGFloat(20)
            let spacing = compact ? CGFloat(9) : CGFloat(11)
            let mapHeight = driveMapHeight(
                containerHeight: proxy.size.height,
                compact: compact,
                topPadding: topPadding,
                bottomPadding: bottomPadding,
                spacing: spacing
            )

            VStack(alignment: .leading, spacing: spacing) {
                header(compact: compact)
                mapCard(compact: compact, height: mapHeight)
                metricsCard(duration: duration, compact: compact)
                actionButton(compact: compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    /*
     Purpose:
     Chooses vertical padding that keeps the drive screen balanced on compact devices.
    */
    private func driveTopPadding(compact: Bool) -> CGFloat {
        compact ? 22 : 34
    }

    /*
     Purpose:
     Chooses a responsive map height for the live drive screen.
    */
    private func driveMapHeight(
        containerHeight: CGFloat,
        compact: Bool,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let headerHeight: CGFloat = compact ? 52 : 62
        let metricsHeight: CGFloat = compact ? 82 : 92
        let driveButtonHeight: CGFloat = compact ? 50 : 56
        let permissionButtonHeight: CGFloat = showsLocationPermissionAction ? (compact ? 48 : 54) + (compact ? 8 : 10) : 0
        let actionAreaPadding: CGFloat = compact ? 10 : 12
        let reservedHeight = topPadding + bottomPadding + headerHeight + metricsHeight + driveButtonHeight + permissionButtonHeight + actionAreaPadding + spacing * 3
        let availableHeight = containerHeight - reservedHeight
        let minimumMapHeight: CGFloat = compact ? 260 : 300
        return max(minimumMapHeight, availableHeight)
    }

    /*
     Purpose:
     Builds the teen drive screen header.
    */
    private func header(compact: Bool) -> some View {
        TeenScreenHeader(title: "Drive", compact: compact) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tracker.isTracking ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                Text(tracker.isTracking ? "Live drive in progress" : "Ready to drive")
                    .foregroundStyle(tracker.isTracking ? Color.green : Color.white.opacity(0.62))
            }
        } actions: {
            NavigationLink {
                safetySettings()
            } label: {
                TeenHeaderCircleIcon(systemName: "bell", compact: compact)
            }
            .buttonStyle(.plain)
        }
    }

    /*
     Purpose:
     Builds the live route map container and overlays current alert markers.
    */
    private func mapCard(compact: Bool, height mapHeight: CGFloat) -> some View {
        TeenLiveDriveMap(
            route: tracker.currentRoute,
            lastKnownLocation: tracker.lastKnownLocation,
            alerts: tracker.currentSafetyAlerts
        )
            .environment(\.teenDriveMapStyle, mapStyle)
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                LinearGradient(
                    colors: [Color.green.opacity(0.12), Color.white.opacity(0.04), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                VStack(spacing: compact ? 6 : 8) {
                    SpeedLimitBadge(
                        limitMPH: tracker.roadSpeedLimitMPH,
                        roadLimitsEnabled: tracker.roadSpeedLimitsEnabled,
                        fallbackLimitMPH: speedLimitMPH
                    )
                    Text(String(format: "%.0f", tracker.speedMPH))
                        .font(.system(size: compact ? 28 : 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    Text("mph")
                        .font(compact ? .subheadline : .headline)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(width: compact ? 76 : 84, height: compact ? 128 : 140)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .padding(.leading, compact ? 14 : 18)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: compact ? 10 : 12) {
                    Button(action: onCenterMap) {
                        Image(systemName: "location.fill")
                            .frame(width: compact ? 40 : 46, height: compact ? 40 : 46)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        mapStyle.toggle()
                    } label: {
                        Image(systemName: "square.3.layers.3d.down.right")
                            .frame(width: compact ? 40 : 46, height: compact ? 40 : 46)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .font((compact ? Font.title3 : .title2).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.trailing, compact ? 14 : 18)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, compact ? 12 : 16)
            }
            .frame(height: mapHeight)
    }

    /*
     Purpose:
     Builds the current drive metric summary card.
    */
    private func metricsCard(duration: String, compact: Bool) -> some View {
        HStack(spacing: 0) {
            DriveMetric(
                icon: "checkmark.shield.fill",
                iconColor: .green,
                title: "Safety Score",
                value: "\(latestScore)",
                detail: scoreLabel,
                compact: compact
            )

            Divider().background(Color.white.opacity(0.16))

            DriveMetric(
                icon: "road.lanes",
                iconColor: .white.opacity(0.22),
                title: "Distance",
                value: String(format: "%.2f mi", tracker.distanceMiles),
                detail: nil,
                compact: compact
            )

            Divider().background(Color.white.opacity(0.16))

            DriveMetric(
                icon: "clock",
                iconColor: .white.opacity(0.22),
                title: "Duration",
                value: duration,
                detail: nil,
                compact: compact
            )
        }
        .frame(height: compact ? 82 : 92)
        .padding(.horizontal, compact ? 8 : 12)
        .teenGlassCard()
    }

    /*
     Purpose:
     Builds the main start, stop, or permission button for drive tracking.
    */
    private func actionButton(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            if showsLocationPermissionAction {
                Button(action: handleLocationPermissionAction) {
                    Label(locationPermissionTitle, systemImage: locationPermissionIcon)
                        .font((compact ? Font.subheadline : .headline).weight(.semibold))
                        .frame(maxWidth: .infinity)
                    .frame(height: compact ? 48 : 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(locationPermissionColor)
                .glassActionButton(accent: locationPermissionColor)
            }

            Button(action: onToggleDrive) {
                Label(tracker.isTracking ? "End Drive" : "Start Drive", systemImage: "car.fill")
                    .font((compact ? Font.headline : .title3).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 50 : 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tracker.isTracking ? .orange : .green)
            .glassActionButton(accent: tracker.isTracking ? .orange : .green)
        }
        .padding(.top, compact ? 4 : 6)
        .padding(.bottom, compact ? 6 : 8)
    }

    /*
     Purpose:
     Routes the permission button to the next needed location authorization step.
    */
    private func handleLocationPermissionAction() {
        switch tracker.authorizationStatus {
        case .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        case .authorizedWhenInUse:
            tracker.requestAlwaysPermission()
        default:
            onRequestPermission()
        }
    }

}

private enum TeenDriveMapStyle {
    case standard
    case satellite

    /*
     Purpose:
     Performs the toggle operation for this file's feature area.
    */
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
    let alerts: [SafetyAlert]
    @Environment(\.teenDriveMapStyle) private var mapStyle
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static var fallbackCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    }

    private static var defaultRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: fallbackCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))
    }

    private var mapRegion: MKCoordinateRegion {
        let alertCoordinates = alerts.compactMap(\.coordinate)
        guard let first = route.first?.coordinate ?? lastKnownLocation?.coordinate ?? alertCoordinates.first else {
            return Self.defaultRegion
        }

        let coordinates = route.map(\.coordinate) + [lastKnownLocation?.coordinate].compactMap { $0 } + alertCoordinates
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
                    .stroke(.green.opacity(0.35), lineWidth: 10)
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(.green, lineWidth: 5)
            }

            if let first = route.first {
                Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                    .tint(.green)
            }

            ForEach(alerts) { alert in
                if let coordinate = alert.coordinate {
                    Marker(alert.kind.title, systemImage: alert.kind.systemImage, coordinate: coordinate)
                        .tint(.orange)
                }
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
        .onChange(of: alerts) {
            updateCamera(animated: true)
        }
    }

    /*
     Purpose:
     Moves the map camera to keep route and alert points visible.
    */
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
                .fill(Color.green.opacity(0.22))
                .frame(width: 54, height: 54)
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 31, height: 31)
            Circle()
                .fill(Color.green)
                .frame(width: 21, height: 21)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

private struct SpeedLimitBadge: View {
    let limitMPH: Double?
    let roadLimitsEnabled: Bool
    let fallbackLimitMPH: Double

    private var isRoadLimit: Bool {
        limitMPH != nil
    }

    private var displayedLimit: String {
        if let limitMPH {
            return String(format: "%.0f", limitMPH)
        }
        return String(format: "%.0f", fallbackLimitMPH)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isRoadLimit ? "ROAD" : roadLimitsEnabled ? "FALL" : "ALERT")
            Text(isRoadLimit ? "LIMIT" : roadLimitsEnabled ? "BACK" : "LIMIT")
            Text(displayedLimit)
                .font(.system(size: displayedLimit.count > 2 ? 18 : 22, weight: .black))
                .minimumScaleFactor(0.8)
                .monospacedDigit()
        }
        .font(.system(size: 8, weight: .black))
        .foregroundStyle(.black)
        .frame(width: 42, height: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isRoadLimit ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}

private struct DriveMetric: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let detail: String?
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 8) {
            Image(systemName: icon)
                .font((compact ? Font.subheadline : .headline).weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: compact ? 20 : 24)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(title)
                    .font((compact ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(value)
                    .font((compact ? Font.subheadline : .headline).bold())
                    .monospacedDigit()
                    .foregroundStyle(title == "Safety Score" ? Color.green : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 4 : 6)
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
                    homeStatTile(icon: "car.fill", color: .green, title: "Trips", value: "\(tripCount)", detail: "Total drives", compact: compact)
                    homeStatTile(icon: "star", color: .green, title: "Avg Score", value: averageScoreText, detail: "All trips", compact: compact)
                    homeStatTile(icon: "checkmark.shield", color: .green, title: "Safe Streak", value: "\(safeStreak)", detail: "Safe drives", compact: compact)
                }

                focusAndParentGrid(compact: compact)
                quickInsights(compact: compact)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, compact ? 22 : 34)
            .padding(.bottom, compact ? 16 : 20)
        }
        .background(GlassAppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await accountStore.syncAccount()
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

    /*
     Purpose:
     Builds the teen home header showing the current profile and status.
    */
    private func homeHeader(compact: Bool) -> some View {
        TeenScreenHeader(title: "TeenDrive", compact: compact) {
            HStack(spacing: 4) {
                Text("Good afternoon,")
                    .foregroundStyle(.white.opacity(0.58))
                Text("\(greetingName)!")
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        } actions: {
            EmptyView()
        }
    }

    /*
     Purpose:
     Builds the prominent safety score summary on the teen home screen.
    */
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
                    Text("You're building safe driving habits.")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
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
        .teenGlassCard()
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

    /*
     Purpose:
     Builds home-screen cards for focus areas and parent connection status.
    */
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
            .teenGlassCard()

            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                Text("Parent Connection")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                        .background(Color.green.opacity(0.18), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountStore.hasConnectedParent ? "Connected" : "Not connected")
                            .font((compact ? Font.subheadline : .headline).bold())
                            .foregroundStyle(.white)
                        Text(accountStore.hasConnectedParent ? accountStore.connectedParentDisplayName : "Pair with a parent to share your progress.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(compact ? 2 : 3)
                    }
                }

                if !accountStore.hasConnectedParent {
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
                    .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 118 : 140, alignment: .topLeading)
            .padding(compact ? 10 : 12)
            .teenGlassCard()
        }
    }

    /*
     Purpose:
     Builds short home-screen guidance rows from the latest trip history.
    */
    private func quickInsights(compact: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                Label("Quick Insights", systemImage: "chart.xyaxis.line")
                    .font((compact ? Font.subheadline : .headline).weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .white)

                insightRow("No harsh braking on your last 3 trips.", compact: compact)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("Best drive this week:")
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(max(safeScore, averageTripScore ?? safeScore))")
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
                .font(compact ? .caption : .subheadline)
            }

            Spacer()

            Button {
                onSelectTab(.reports)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                    .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                    .teenGlassControl()
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: compact ? 76 : 92)
        .padding(compact ? 10 : 14)
        .teenGlassCard()
    }

    private var scoreHeadline: String {
        safeScore >= 85 ? "Great job!" : safeScore >= 70 ? "Good progress" : "Needs focus"
    }

    /*
     Purpose:
     Builds one compact statistic tile on the teen home screen.
    */
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
        .teenGlassCard()
    }

    /*
     Purpose:
     Builds one readable insight row for the teen home screen.
    */
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

    /*
     Purpose:
     Builds one row in the trip behavior score penalty breakdown.
    */
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

/*
 Purpose:
 Draws the shared dark glass backdrop used behind the Music-style translucent surfaces.
*/
struct GlassAppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.04, blue: 0.05),
                Color(red: 0.07, green: 0.09, blue: 0.11),
                Color(red: 0.01, green: 0.02, blue: 0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.11),
                    Color.green.opacity(0.08),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /*
     Purpose:
     Applies the app's translucent glass card treatment used across dashboard panels and lists.
    */
    func teenGlassCard(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
    }

    /*
     Purpose:
     Applies a smaller glass treatment for icon buttons, rows, and secondary controls.
    */
    func teenGlassControl(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    /*
     Purpose:
     Styles primary action buttons as translucent glass while preserving a clear accent color.
    */
    func glassActionButton(accent: Color) -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.2),
                                Color.white.opacity(0.08),
                                accent.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), accent.opacity(0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: accent.opacity(0.18), radius: 16, y: 7)
    }
}
