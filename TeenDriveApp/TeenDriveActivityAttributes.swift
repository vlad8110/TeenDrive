/*
 File: TeenDriveActivityAttributes.swift
 Created: 2026-05-08
 Creator: Vladimyr Merci

 Purpose:
 Defines the ActivityKit state shared by the main app and the Live Activity widget extension.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import ActivityKit
import Foundation

struct TeenDriveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedMetersPerSecond: Double
        var topSpeedMetersPerSecond: Double
        var distanceMeters: Double
    }

    var activityName: String
}
