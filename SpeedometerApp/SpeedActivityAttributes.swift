import ActivityKit
import Foundation

struct SpeedActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedMetersPerSecond: Double
        var topSpeedMetersPerSecond: Double
        var distanceMeters: Double
        var startedAt: Date
        var updatedAt: Date
    }

    var activityName: String
}
