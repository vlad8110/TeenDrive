# Teen Drive

An iOS SwiftUI teen driving tracker MVP with local trip history, route maps, speed alerts, and a Live Activity.

## What It Does

- Tracks current speed from GPS using Core Location.
- Shows current speed, top speed, and distance in the app.
- Starts a Live Activity while tracking so speed stays visible outside the app.
- Saves each driving trip by date and time.
- Shows saved trip routes on a map.
- Records local speed alerts when a trip crosses 75 mph.
- Includes a parent dashboard with active drive status, last known location during active tracking, trip route previews, and trip safety metrics.
- Selects Teen or Parent mode on first app start.
- Keeps the Parent dashboard hidden in Teen mode.
- Lets Teen mode operate independently before pairing.
- Lets Parent mode connect to multiple teens with QR pairing.
- Uses Firebase Auth for anonymous MVP accounts once Firebase is configured.
- Stores FamilyGroup, TeenProfile, and ParentProfile records in Firestore.
- Syncs completed teen trips to Firestore and lets the parent dashboard read paired teen trips from Firestore.
- Registers Firebase Cloud Messaging tokens and records notification events for trip started, trip ended, speed alerts, and arrivals.
- On the free Firebase plan, parent devices see synced trip data when they open the app; server push to parent devices is optional later.
- Shows the connected parent account on the teen dashboard after pairing.
- Lets families toggle optional alerts for speed, driving events, trip started, trip ended, and saved-place arrivals.
- Lets families save the teen's last known location as Home, School, or Work for local arrival alerts.
- Records speed-over-limit and rapid acceleration / harsh stop events in each trip and summarizes them in a safety strip.
- Arms automatic tracking and starts a session when speed passes 5 mph.
- Stops and saves the session after 5 minutes with no movement.

## Background Tracking

The app requests Always location access so it can auto-start while in the background. iOS still requires the user to open the app at least once and approve location permission. Tracking status is visible in the app and Live Activity. Last known location is shown only while a drive is actively tracking and location updates are available.

## Run It

Open `TeenDrive.xcodeproj` in Xcode, choose an iPhone simulator or device, and run the `TeenDrive` scheme.

Live Activities work best on a real device. The simulator can run the app, but GPS speed updates need simulated location changes.

## Firebase Setup

1. Create a Firebase iOS app with bundle id `com.vlad8110.teendrive`.
2. Download `GoogleService-Info.plist` from Firebase Console.
3. Add it to `TeenDriveApp/GoogleService-Info.plist` and include it in the TeenDrive app target.
4. Enable Anonymous sign-in in Firebase Auth.
5. Enable Cloud Firestore.
6. Enable Cloud Messaging and add APNs credentials in Firebase Console when you are ready for real device push delivery.

## Free Firebase Plan

The app works on the free Firebase plan for:

- Anonymous Firebase Auth accounts.
- Firestore family groups, parent profiles, and teen profiles.
- Synced completed trips.
- Parent dashboard trip history when the parent opens the app.
- Local notifications on the teen device.
- Stored `notificationEvents` records for later server processing.

Deploy only the Firestore rules/index config:

```bash
firebase deploy --only firestore
```

Do not deploy Functions on the free plan. Cloud Functions requires the Blaze plan.

## Optional Push Server Later

The `functions/` folder contains an optional Cloud Function that watches `notificationEvents` and sends Firebase Cloud Messaging pushes to connected parent devices. Keep it for later.

When you upgrade to Blaze, deploy it with:

```bash
firebase deploy --config firebase-functions.blaze.json --only functions
```
