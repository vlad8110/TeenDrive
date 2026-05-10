/*
 File: SafetyAlertSettingsView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Presents the settings form for safety alert categories, drive status alerts, speed limits, and saved places.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import SwiftUI

struct SafetyAlertSettingsView: View {
    @ObservedObject var settings: SafetyAlertSettings
    @ObservedObject var tracker: TeenDriveTracker

    var body: some View {
        Form {
            Section("Safety Alerts") {
                Toggle("Speed over limit", isOn: $settings.speedAlertsEnabled)
                Toggle("Hard acceleration, stop, or turn", isOn: $settings.drivingEventAlertsEnabled)
                Toggle("Night driving", isOn: $settings.nightDrivingAlertsEnabled)
                Toggle("Phone use while moving", isOn: $settings.phoneUseAlertsEnabled)
                Toggle("Arrived at saved places", isOn: $settings.placeArrivalAlertsEnabled)
            }

            Section("Drive Status Alerts") {
                Toggle("Drive started", isOn: $settings.tripStartedAlertsEnabled)
                Toggle("Drive ended", isOn: $settings.tripEndedAlertsEnabled)
            }

            Section("Speed Limit") {
                Toggle("Use road speed limits", isOn: $settings.roadSpeedLimitsEnabled)

                Stepper(value: $settings.speedLimitMPH, in: 25...100, step: 5) {
                    HStack {
                        Text(settings.roadSpeedLimitsEnabled ? "Fallback alert at" : "Alert at")
                        Spacer()
                        Text(String(format: "%.0f mph", settings.speedLimitMPH))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Road limits use available OpenStreetMap data. The fallback limit is used when the current road has no mapped speed limit or the lookup is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Saved Places") {
                if let point = tracker.lastKnownLocation {
                    Button("Save Last Location as Home") {
                        settings.savePlace(named: "Home", point: point)
                    }
                    Button("Save Last Location as School") {
                        settings.savePlace(named: "School", point: point)
                    }
                    Button("Save Last Location as Work") {
                        settings.savePlace(named: "Work", point: point)
                    }
                } else {
                    Text("Start tracking once to capture a location before saving Home, School, or Work.")
                        .foregroundStyle(.secondary)
                }

                ForEach(settings.savedPlaces) { place in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                        Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: settings.deletePlaces)
            }
        }
        .navigationTitle("Safety Alerts")
    }
}
