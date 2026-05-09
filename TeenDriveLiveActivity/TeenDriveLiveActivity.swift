import ActivityKit
import SwiftUI
import WidgetKit

struct TeenDriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeenDriveActivityAttributes.self) { context in
            LockScreenSpeedView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("Teen Drive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.speedText)
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("Top")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.topSpeedText)
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.distanceText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Spacer()
                        Text(context.state.updatedAt, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "speedometer")
            } compactTrailing: {
                Text(context.state.speedNumberText)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "speedometer")
            }
            .widgetURL(URL(string: "teendrive://activity"))
            .keylineTint(.green)
        }
    }
}

private struct LockScreenSpeedView: View {
    let state: TeenDriveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speedometer")
                .font(.title)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Teen Drive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.speedText)
                    .font(.title.bold())
                    .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Top")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(state.topSpeedText)
                    .font(.headline.bold())
                    .monospacedDigit()
                Text(state.distanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private extension TeenDriveActivityAttributes.ContentState {
    var speedMPH: Double {
        max(speedMetersPerSecond, 0) * 2.2369362921
    }

    var topSpeedMPH: Double {
        max(topSpeedMetersPerSecond, 0) * 2.2369362921
    }

    var speedText: String {
        String(format: "%.0f mph", speedMPH)
    }

    var topSpeedText: String {
        String(format: "%.0f mph", topSpeedMPH)
    }

    var speedNumberText: String {
        String(format: "%.0f", speedMPH)
    }

    var distanceText: String {
        String(format: "%.2f mi", distanceMeters / 1609.344)
    }
}
