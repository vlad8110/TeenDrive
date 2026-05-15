/*
 File: PrivacySafetyView.swift
 Created: 2026-05-12
 Creator: Vladimyr Merci

 Purpose:
 Shows the in-app privacy policy summary, safety disclaimer, and account/data deletion explanation.

 Developer Notes:
 Keep this screen aligned with PRIVACY_POLICY.md and SAFETY_DISCLAIMER.md when the product language changes.
*/
import SwiftUI

// Presents user-facing legal and safety information from the Profile screen.
struct PrivacySafetyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                legalSection(
                    title: "Privacy Policy",
                    icon: "lock.shield.fill",
                    rows: [
                        "TeenDrive collects account role, display name, pairing links, completed trip summaries, safety alerts, active-drive status, and notification event records needed for parent alerts.",
                        "Driving data can include route points, speed, timestamps, phone-use alerts, night-driving alerts, harsh driving events, and over-speed-limit alerts.",
                        "Data is stored on the device and, when Firebase is configured, synced to Firestore so paired parents can see connected teen trips and active-drive status."
                    ]
                )

                legalSection(
                    title: "Safety Disclaimer",
                    icon: "exclamationmark.triangle.fill",
                    rows: [
                        "TeenDrive is a coaching and awareness tool. It is not a crash detector, emergency service, legal driving record, or replacement for driver supervision.",
                        "Location, speed limit, phone-use, and motion detection can be delayed, unavailable, or inaccurate because they depend on iOS permissions, GPS quality, network access, and sensor conditions.",
                        "Drivers must follow traffic laws and should never interact with the phone while driving."
                    ]
                )

                legalSection(
                    title: "Delete Account & Data",
                    icon: "trash.fill",
                    rows: [
                        "Use Profile > Delete Account & Data to remove local trips, pairing links, and account settings from this device.",
                        "Teen accounts also request deletion of synced trips, active-drive status, notification events, pairing tokens, and teen profile records.",
                        "Parent accounts remove parent profile records and parent links from connected teen records without deleting the teen's driving history."
                    ]
                )
            }
            .padding()
        }
        .background(GlassAppBackground())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Privacy & Safety")
        .navigationBarTitleDisplayMode(.inline)
    }

    /*
     Purpose:
     Builds one glass card section containing a title, icon, and short policy bullets.
    */
    private func legalSection(title: String, icon: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.semibold))

            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.green.opacity(0.85))
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)

                    Text(row)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .teenGlassCard()
    }
}
