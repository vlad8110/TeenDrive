# Teen Drive

Teen Drive is an iOS SwiftUI teen driving tracker for families. It records trips, shows live speed and route data, detects safety events, syncs paired teen/parent accounts through Firebase, and gives parents a live dashboard while a teen drive is active.

## Current Features

- Teen and Parent modes selected on first launch.
- Teen mode can work locally before pairing.
- Parent mode can connect to multiple teens by scanning a QR code.
- Pairing QR codes include short-lived cloud tokens so parent linking must be verified by Firestore rules.
- Live drive tracking with current speed, top speed, distance, route, and tracking status.
- Automatic trip start when speed passes 5 mph.
- Automatic trip stop after 5 minutes with no movement.
- Saved trip history with route maps, alert summaries, and behavior score breakdown.
- Parent dashboard with active teen drives, live route maps, alert pins, trip history, and safety metrics.
- Lock Screen Live Activity during active tracking. Dynamic Island content is intentionally blank.
- In-app privacy policy, safety disclaimer, and account/data deletion from Profile.

## Safety Alerts

Teen Drive records safety alerts during trips and shows them in trip summaries, live parent views, and map pins when a location is available.

Current alert types:

- Speed over limit
- Rapid acceleration
- Harsh stop
- Harsh cornering
- Night driving
- Phone use or phone unlocked while moving
- Arrival at saved places

Drive status alerts are tracked separately:

- Drive started
- Drive ended

Status alerts explain trip lifecycle events but do not count as safety alerts in the trip safety count.

## Speed Limit Alerts

Speed alerts use road speed limits when available.

- Road limits are looked up from OpenStreetMap Overpass data.
- If no mapped road limit is found, the app uses the fallback speed limit from Safety Settings.
- The default fallback limit is 45 mph.
- The fallback limit can be changed from 25 mph to 100 mph.
- A speed alert requires the teen to be at least 3 mph over the active limit for 3 seconds.
- U.S. OpenStreetMap speed values without units are treated as mph.

## Phone Use Detection

iOS does not expose exact phone activity such as every unlock, tap, or app switch. Teen Drive uses lightweight signals that are available without Family Controls:

- App opened while a drive is active.
- Protected data became available, which is a practical signal that the phone was unlocked.

Phone-use alerts only record while driving, after the trip has been active for at least 30 seconds, at 10 mph or faster, and with a cooldown to avoid repeated alerts.

## Privacy, Safety, And Data Deletion

Privacy and safety information is available inside the app from Profile > Privacy & Safety.

- `PRIVACY_POLICY.md` describes what the app collects, why it collects it, where it stores data, and how deletion works.
- `SAFETY_DISCLAIMER.md` explains that Teen Drive is a coaching tool, not an emergency service, crash detector, legal driving record, or replacement for safe supervision.
- Profile > Delete Account & Data clears local trip history and account settings from the device.
- Teen deletion requests also remove synced teen trips, active-drive status, notification events, pairing tokens, teen profile records, and family teen records.
- Parent deletion requests remove parent profile records and parent links without deleting the teen's driving history.

## Background Tracking

The app requests Always Location access so it can auto-start drives and keep tracking in the background.

Important notes:

- iOS still requires the user to open the app at least once and approve location permission.
- Background tracking depends on iOS location behavior and device settings.
- Live tracking status is visible inside the app and on the Lock Screen Live Activity.
- Last known location is shared only while a drive is actively tracking and a valid location is available.

## Firebase Sync

Teen Drive can run locally, but family pairing and parent dashboards use Firebase.

Firebase is used for:

- Anonymous Firebase Auth accounts.
- Family group records.
- Teen and parent profile records.
- Short-lived pairing tokens for QR-based parent connection.
- Completed trip sync.
- Active-drive sync for the parent live dashboard.
- Safety alert notification events.
- Firebase Cloud Messaging tokens for parent push notifications.

The app looks for `TeenDriveApp/GoogleService-Info.plist`. If it is missing, local tracking still works, but cloud features are unavailable.

## Firebase Setup

1. Create a Firebase iOS app with bundle id `com.vlad8110.teendrive`.
2. Download `GoogleService-Info.plist` from Firebase Console.
3. Add it to `TeenDriveApp/GoogleService-Info.plist`.
4. Make sure the plist is included in the TeenDrive app target.
5. Enable Anonymous sign-in in Firebase Auth.
6. Enable Cloud Firestore.
7. Enable Cloud Messaging.
8. Add APNs credentials in Firebase Console for real-device push delivery.
9. Deploy Firestore rules and indexes.

```bash
firebase deploy --only firestore
```

## Cloud Functions

The `functions/` folder contains a Firebase Cloud Function that watches `notificationEvents` and sends Firebase Cloud Messaging pushes to connected parent devices.

Cloud Functions require the Firebase Blaze plan.

Deploy functions with:

```bash
firebase deploy --config firebase-functions.blaze.json --only functions
```

Useful function commands:

```bash
cd functions
npm run build
npm run lint
npm run serve
```

## Run The App

Open `TeenDrive.xcodeproj` in Xcode, choose an iPhone simulator or device, and run the `TeenDrive` scheme.

Real-device testing is recommended for:

- Background location behavior.
- Lock Screen Live Activity.
- Push notifications.
- Camera QR scanning.
- Real GPS speed and route data.

The simulator can run the app, but speed and route testing require simulated location changes.

## Project Structure

- `TeenDriveApp/` - main SwiftUI iOS app.
- `TeenDriveLiveActivity/` - WidgetKit Live Activity extension.
- `TeenDriveTests/` - unit tests for trip scoring, alert counting, and map-region logic.
- `functions/` - optional Firebase Cloud Function for parent push notifications.
- `firestore.rules` - Firestore security rules.
- `firestore.indexes.json` - Firestore index configuration.
- `firebase.json` - Firebase project config for Firestore deployment.
- `firebase-functions.blaze.json` - Firebase config for deploying Cloud Functions on Blaze.

## Important iOS Files

- `TeenDriveApp/Info.plist` declares location, camera, background mode, and Live Activity support.
- `TeenDriveApp/TeenDrive.entitlements` enables APNs push notification support. Debug builds use development APNs and Release builds use production APNs through the `APS_ENVIRONMENT` build setting.
- `TeenDriveApp/GoogleService-Info.plist` connects the app to Firebase.

## App Store Release Prep

App Store submission materials live in `docs/app-store/`.

- `APP_STORE_METADATA.md` - draft app name, subtitle, description, keywords, category, and review notes.
- `PRIVACY_NUTRITION_LABELS.md` - App Store Connect privacy label draft for the current codebase.
- `SCREENSHOT_PLAN.md` - required screenshot sizes and capture storyboard.
- `PRODUCTION_FIREBASE_APNS.md` - production Firebase, APNs, and real-device smoke test checklist.
- `APP_STORE_RELEASE_CHECKLIST.md` - final submission checklist.

## Build Checks

Recommended checks before committing:

```bash
xcodebuild -project TeenDrive.xcodeproj -scheme TeenDrive -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -project TeenDrive.xcodeproj -scheme TeenDrive -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
cd functions && npm run build && npm run lint
```
