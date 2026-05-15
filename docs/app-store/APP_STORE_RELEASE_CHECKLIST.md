# App Store Release Checklist

Created: 2026-05-12  
Creator: Vladimyr Merci

## Metadata

- App name: Teen Drive.
- Subtitle: Family driving safety tracker.
- Description: use `APP_STORE_METADATA.md`.
- Keywords: use `APP_STORE_METADATA.md`.
- Privacy policy URL: publish `PRIVACY_POLICY.md` and paste the public URL into App Store Connect.
- Support URL: add a real support page or contact page.
- Category: Navigation primary, Lifestyle secondary.
- Review notes: include QR pairing and Firebase explanation from `APP_STORE_METADATA.md`.

## Privacy

- Complete App Store privacy answers from `PRIVACY_NUTRITION_LABELS.md`.
- Confirm no analytics, Crashlytics, ads, or tracking SDKs were added after this draft.
- Confirm account/data deletion is visible from Profile.
- Confirm the in-app Privacy & Safety screen matches the hosted privacy policy.

## Screenshots

- Capture iPhone 6.9-inch screenshots.
- Capture iPad 13-inch screenshots because the app supports iPad.
- Follow `SCREENSHOT_PLAN.md`.
- Use demo routes and fake family names.
- Avoid exact private addresses.

## Production Firebase

- Replace local plist with production `TeenDriveApp/GoogleService-Info.plist`.
- Enable Anonymous Auth.
- Enable Cloud Firestore.
- Enable Cloud Messaging.
- Deploy Firestore rules and indexes.
- Deploy Cloud Functions if parent push notifications are part of the release.
- Run the real-device production smoke test in `PRODUCTION_FIREBASE_APNS.md`.

## Production APNs

- Confirm Push Notifications capability on the Apple app identifier.
- Upload APNs Auth Key to Firebase.
- Confirm Debug APNs entitlement is development.
- Confirm Release APNs entitlement is production.
- Confirm TestFlight push notifications work on a real device.

## Build

Recommended pre-submission commands:

```bash
xcodebuild -project TeenDrive.xcodeproj -scheme TeenDrive -configuration Release -destination 'generic/platform=iOS' archive
xcodebuild -project TeenDrive.xcodeproj -scheme TeenDrive -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' test
cd functions && npm run build && npm run lint
```

## Manual QA

- First launch role selection works.
- Teen drive start/stop works.
- Auto-start and auto-stop behavior works on a real route.
- Safety alerts appear on maps.
- Reports can be deleted and stay deleted.
- Parent QR pairing works.
- Parent dashboard shows active drive.
- Parent dashboard shows completed trip.
- Phone-unlock alert records only while driving.
- Privacy & Safety opens.
- Delete Account & Data resets the app and cleans test Firestore records.

## Do Not Submit Until

- Cloud Sync is Up to date on a production TestFlight build.
- App Review has valid login/review steps.
- Hosted privacy policy URL is live.
- Production Firebase project is selected.
- Push notification delivery is verified on a real device.
