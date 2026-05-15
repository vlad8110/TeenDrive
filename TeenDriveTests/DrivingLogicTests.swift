/*
 File: DrivingLogicTests.swift
 Created: 2026-05-12
 Creator: Vladimyr Merci

 Purpose:
 Verifies the core trip scoring and alert-counting rules used by the TeenDrive reports.

 Developer Notes:
 These tests stay at the model layer so they run quickly and do not require GPS, Firebase, or UI state.
*/
import XCTest
@testable import TeenDrive

// Tests the pure driving logic that turns trip data into safety counts and scores.
final class DrivingLogicTests: XCTestCase {
    /*
     Purpose:
     Confirms trip lifecycle events are stored for context but do not inflate safety-alert counts.
    */
    func testLifecycleAlertsDoNotCountAsSafetyAlerts() {
        let trip = makeTrip(
            safetyAlerts: [
                makeAlert(kind: .tripStarted),
                makeAlert(kind: .tripEnded),
                makeAlert(kind: .rapidAcceleration)
            ]
        )

        XCTAssertEqual(trip.safetyAlertCount, 1)
        XCTAssertEqual(trip.rapidAccelerationAlertCount, 1)
        XCTAssertEqual(trip.displaySafetyAlerts.map(\.kind), [.rapidAcceleration])
    }

    /*
     Purpose:
     Confirms legacy speed-alert records still appear as safety alerts when no newer safety events exist.
    */
    func testLegacySpeedAlertsBackfillDisplaySafetyAlerts() {
        let trip = makeTrip(
            speedAlerts: [
                SpeedAlert(
                    id: UUID(),
                    timestamp: Date(),
                    speedMetersPerSecond: 24,
                    latitude: 25.76,
                    longitude: -80.19
                )
            ],
            safetyAlerts: []
        )

        XCTAssertEqual(trip.safetyAlertCount, 1)
        XCTAssertEqual(trip.speedLimitAlertCount, 1)
        XCTAssertEqual(trip.displaySafetyAlerts.first?.kind, .speedLimit)
    }

    /*
     Purpose:
     Confirms behavior scoring deducts points for top speed, speeding, and harsh driving events.
    */
    func testBehaviorScorePenalizesRiskyDrivingEvents() {
        let trip = makeTrip(
            duration: 30 * 60,
            topSpeedMetersPerSecond: 38,
            safetyAlerts: [
                makeAlert(kind: .speedLimit),
                makeAlert(kind: .speedLimit),
                makeAlert(kind: .harshStop),
                makeAlert(kind: .harshCornering),
                makeAlert(kind: .phoneUse)
            ]
        )

        let breakdown = trip.behaviorScoreBreakdown

        XCTAssertLessThan(breakdown.score, 100)
        XCTAssertEqual(breakdown.speedingPenalty, 10)
        XCTAssertEqual(breakdown.drivingEventPenalty, 14)
        XCTAssertEqual(breakdown.harshStopPenalty, 4)
        XCTAssertGreaterThan(breakdown.alertRatePenalty, 0)
    }

    /*
     Purpose:
     Confirms route and alert coordinates are both considered when building the map region.
    */
    func testMapRegionIncludesSafetyAlertLocations() {
        let trip = makeTrip(
            safetyAlerts: [
                makeAlert(kind: .speedLimit, latitude: 26.0, longitude: -81.0)
            ],
            route: [
                RoutePoint(latitude: 25.0, longitude: -80.0, timestamp: Date())
            ]
        )

        XCTAssertEqual(trip.mapRegion.center.latitude, 25.5, accuracy: 0.001)
        XCTAssertEqual(trip.mapRegion.center.longitude, -80.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(trip.mapRegion.span.latitudeDelta, 1.5)
        XCTAssertGreaterThanOrEqual(trip.mapRegion.span.longitudeDelta, 1.5)
    }

    /*
     Purpose:
     Creates a reusable trip fixture with sensible defaults for model-layer tests.
    */
    private func makeTrip(
        duration: TimeInterval = 15 * 60,
        topSpeedMetersPerSecond: Double = 20,
        speedAlerts: [SpeedAlert] = [],
        safetyAlerts: [SafetyAlert] = [],
        route: [RoutePoint] = []
    ) -> TeenTrip {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return TeenTrip(
            id: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            distanceMeters: 2_000,
            topSpeedMetersPerSecond: topSpeedMetersPerSecond,
            speedAlerts: speedAlerts,
            safetyAlerts: safetyAlerts,
            route: route
        )
    }

    /*
     Purpose:
     Creates a safety alert fixture with optional coordinates for map-related tests.
    */
    private func makeAlert(
        kind: SafetyAlertKind,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> SafetyAlert {
        SafetyAlert(
            kind: kind,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            speedMetersPerSecond: 20,
            latitude: latitude,
            longitude: longitude,
            note: kind.title
        )
    }
}
