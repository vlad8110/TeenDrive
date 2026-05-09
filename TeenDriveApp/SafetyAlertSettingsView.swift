import SwiftUI

struct SafetyAlertSettingsView: View {
    @ObservedObject var settings: SafetyAlertSettings
    @ObservedObject var tracker: TeenDriveTracker

    var body: some View {
        Form {
            Section("Optional Alerts") {
                Toggle("Speed over limit", isOn: $settings.speedAlertsEnabled)
                Toggle("Rapid acceleration / harsh stop", isOn: $settings.drivingEventAlertsEnabled)
                Toggle("Trip started", isOn: $settings.tripStartedAlertsEnabled)
                Toggle("Trip ended", isOn: $settings.tripEndedAlertsEnabled)
                Toggle("Arrived at saved places", isOn: $settings.placeArrivalAlertsEnabled)
            }

            Section("Speed Limit") {
                Stepper(value: $settings.speedLimitMPH, in: 45...100, step: 5) {
                    HStack {
                        Text("Alert at")
                        Spacer()
                        Text(String(format: "%.0f mph", settings.speedLimitMPH))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
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
