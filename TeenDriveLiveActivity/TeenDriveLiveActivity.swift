import ActivityKit
import SwiftUI
import WidgetKit

struct TeenDriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TeenDriveActivityAttributes.self) { context in
            LockScreenSpeedView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
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

    var distanceText: String {
        String(format: "%.2f mi", distanceMeters / 1609.344)
    }
}
