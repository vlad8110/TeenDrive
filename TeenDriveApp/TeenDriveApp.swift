/*
 File: TeenDriveApp.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Provides the SwiftUI application entry point and installs the UIKit app delegate.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import SwiftUI

@main
struct TeenDriveApp: App {
    @UIApplicationDelegateAdaptor(TeenDriveAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
