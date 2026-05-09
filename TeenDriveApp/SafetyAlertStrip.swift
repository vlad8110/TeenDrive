import SwiftUI

struct SafetyAlertStrip: View {
    let session: TeenTrip

    var body: some View {
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
                title: "Harsh Stop",
                value: "\(session.harshStopAlertCount)",
                systemImage: "exclamationmark.octagon.fill",
                color: session.harshStopAlertCount > 0 ? .orange : .secondary
            )
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
        .frame(maxWidth: .infinity)
    }
}
