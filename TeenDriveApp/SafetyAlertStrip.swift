import SwiftUI

struct SafetyAlertStrip: View {
    let session: TeenTrip

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StripItem(
                    title: "Over Limit",
                    value: "\(session.speedLimitAlertCount)",
                    systemImage: "speedometer",
                    color: session.speedLimitAlertCount > 0 ? .orange : .secondary
                )
                StripItem(
                    title: "Rapid",
                    value: "\(session.rapidAccelerationAlertCount)",
                    systemImage: "bolt.fill",
                    color: session.rapidAccelerationAlertCount > 0 ? .orange : .secondary
                )
                StripItem(
                    title: "Stop",
                    value: "\(session.harshStopAlertCount)",
                    systemImage: "exclamationmark.octagon.fill",
                    color: session.harshStopAlertCount > 0 ? .orange : .secondary
                )
                StripItem(
                    title: "Corner",
                    value: "\(session.harshCorneringAlertCount)",
                    systemImage: "arrow.turn.up.right",
                    color: session.harshCorneringAlertCount > 0 ? .orange : .secondary
                )
                StripItem(
                    title: "Phone",
                    value: "\(session.phoneUseAlertCount)",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    color: session.phoneUseAlertCount > 0 ? .orange : .secondary
                )
                StripItem(
                    title: "Night",
                    value: "\(session.nightDrivingAlertCount)",
                    systemImage: "moon.stars.fill",
                    color: session.nightDrivingAlertCount > 0 ? .orange : .secondary
                )
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StripItem: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Label(value, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 66)
    }
}
