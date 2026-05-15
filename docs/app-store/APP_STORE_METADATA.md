# TeenDrive App Store Metadata

Created: 2026-05-12  
Creator: Vladimyr Merci

## App Name

Teen Drive

## Subtitle

Family driving safety tracker

## Promotional Text

Help families review teen drives with route history, live drive status, safety alerts, and parent pairing.

## Description

Teen Drive helps families coach safer teen driving with clear trip reports, route maps, and safety alerts.

Teen drivers can record trips, review distance, duration, top speed, and safety score, and see where alerts happened on the map. Parents can pair with a teen by scanning a QR code, then review completed trips and active drive status from their own dashboard.

Teen Drive currently tracks:

- Speed over limit
- Rapid acceleration
- Harsh stops
- Harsh cornering
- Night driving
- Phone opened or unlocked while driving
- Arrival at saved places

The app is built for family awareness and conversation. It is not a crash detector, emergency response service, insurance telematics product, legal driving record, or replacement for responsible supervision.

## Keywords

teen driver,parent driving,driving safety,trip tracker,family safety,speed alert,driving report,teen safety

## Primary Category

Navigation

## Secondary Category

Lifestyle

## Age Rating Notes

The app does not include user-generated public content, commerce, gambling, alcohol, tobacco, or medical treatment features. It does collect location and driving behavior data for family safety review. Recommended App Store age rating target: 4+ unless App Store Connect questionnaire responses require otherwise.

## Support URL

Add the production support page URL before submission.

## Marketing URL

Optional. Add a public product page if available.

## Privacy Policy URL

Add a hosted version of `PRIVACY_POLICY.md` before submission. App Store Connect requires a URL, not only an in-app or repository file.

## Copyright

2026 Vladimyr Merci

## Review Notes

Teen Drive uses location in the background to detect active driving, save trip routes, and show paired parents live drive status. Parent pairing uses QR scanning and Firebase anonymous authentication. Push notifications are used for parent safety alerts.

Test path:

1. Launch the app.
2. Choose Teen mode.
3. Open Profile and wait for Cloud Sync to show up to date.
4. Generate the pairing QR.
5. On another installation, choose Parent mode and scan the QR.
6. Start a teen drive to see live status and completed trip reports.

If Firebase credentials are not available in the review build, local teen drive tracking still works, but parent pairing and cloud sync require the bundled production `GoogleService-Info.plist`.
