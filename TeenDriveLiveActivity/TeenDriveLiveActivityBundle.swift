/*
 File: TeenDriveLiveActivityBundle.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Registers the Live Activity widget with WidgetKit.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import WidgetKit
import SwiftUI

@main
struct TeenDriveLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TeenDriveLiveActivity()
    }
}
