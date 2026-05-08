# Speedometer

An iOS SwiftUI speed tracker with a Live Activity for the Lock Screen and Dynamic Island.

## What It Does

- Tracks current speed from GPS using Core Location.
- Shows current speed, top speed, and distance in the app.
- Starts a Live Activity while tracking so speed stays visible outside the app.
- Saves each tracking session by date and time.
- Shows saved session routes on a map.
- Arms automatic tracking and starts a session when speed passes 5 mph.

## Background Tracking

The app requests Always location access so it can auto-start while in the background. iOS still requires the user to open the app at least once and approve location permission.

## Run It

Open `Speedometer.xcodeproj` in Xcode, choose an iPhone simulator or device, and run the `Speedometer` scheme.

Live Activities work best on a real device. The simulator can run the app, but GPS speed updates need simulated location changes.
