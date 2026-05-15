# Production Firebase And APNs Checklist

Created: 2026-05-12  
Creator: Vladimyr Merci

## Bundle IDs

Main app:

- `com.vlad8110.teendrive`

Live Activity extension:

- `com.vlad8110.teendrive.liveactivity`

## APNs Entitlement Setup

The app entitlement now uses a build setting:

- Debug: `APS_ENVIRONMENT = development`
- Release: `APS_ENVIRONMENT = production`

This keeps local debug notification testing on the APNs sandbox while App Store builds use production APNs.

## Apple Developer Portal

1. Open Certificates, Identifiers & Profiles.
2. Confirm the app identifier `com.vlad8110.teendrive` has Push Notifications enabled.
3. Create or reuse an APNs Auth Key with Apple Push Notifications service enabled.
4. Record:
   - Key ID.
   - Team ID.
   - `.p8` key file.
5. Make sure the App Store provisioning profile includes Push Notifications.

## Firebase Production Project

Create or confirm a production Firebase project separate from development testing.

Required Firebase products:

- Firebase Authentication with Anonymous sign-in enabled.
- Cloud Firestore.
- Firebase Cloud Messaging.
- Cloud Functions if parent push notifications are enabled.

## Production `GoogleService-Info.plist`

1. In Firebase Console, add an iOS app with bundle ID `com.vlad8110.teendrive`.
2. Download the production `GoogleService-Info.plist`.
3. Place it at `TeenDriveApp/GoogleService-Info.plist` for the App Store build.
4. Confirm the plist is included in the TeenDrive target resources.
5. Do not use a development Firebase plist for App Store submission.

## Upload APNs Key To Firebase

1. Open Firebase Console.
2. Go to Project Settings.
3. Open the Cloud Messaging tab.
4. Under the iOS app configuration, upload the APNs authentication key.
5. Enter the Key ID and Apple Team ID.
6. Confirm Firebase shows the key for the production app.

## Deploy Firebase Backend

Deploy Firestore rules and indexes:

```bash
firebase deploy --only firestore
```

Deploy notification Cloud Functions when using parent push notifications:

```bash
firebase deploy --config firebase-functions.blaze.json --only functions
```

## Production Smoke Test

Use a real iPhone for this test because push notifications, APNs tokens, background location, and Live Activities cannot be fully validated in the simulator.

1. Install a Release/TestFlight build.
2. Choose Teen mode.
3. Grant location and notification permissions.
4. Open Profile and confirm Cloud Sync becomes Up to date.
5. Confirm QR pairing appears.
6. Install the same build on a parent device.
7. Choose Parent mode and scan the teen QR.
8. Start a teen drive.
9. Confirm parent dashboard sees active drive status.
10. Trigger a safe test alert and confirm parent notification delivery.
11. Stop the trip and confirm the parent can see the report.
12. Test Delete Account & Data on a disposable test account.

## Release Blockers

- Cloud Sync still shows "Missing or insufficient permissions."
- QR pairing never becomes ready.
- Parent cannot see completed trips.
- Parent push notification is not delivered on a real device.
- Firestore rules are not deployed to the production Firebase project.
- App Store privacy policy URL is missing.
