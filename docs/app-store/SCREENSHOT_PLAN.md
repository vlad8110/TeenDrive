# App Store Screenshot Plan

Created: 2026-05-12  
Creator: Vladimyr Merci

Apple currently accepts one to ten screenshots per device display size. If the interface is the same across device sizes, App Store Connect can scale from the highest required resolution.

## Required Sets For TeenDrive

TeenDrive supports iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), so prepare:

- iPhone 6.9-inch display screenshots.
- iPad 13-inch display screenshots.

## Current Apple Sizes To Export

### iPhone 6.9-inch

Use portrait screenshots in one of these accepted sizes:

- 1260 x 2736
- 1290 x 2796
- 1320 x 2868

Recommended for this app: 1320 x 2868 if captured from iPhone 16 Pro Max or equivalent App Store Connect accepted device.

### iPad 13-inch

Use portrait screenshots in one of these accepted sizes:

- 2064 x 2752
- 2048 x 2732

Recommended for this app: 2064 x 2752 if captured from a current 13-inch iPad simulator.

## Screenshot Storyboard

1. **Drive dashboard**  
   Show the glass map, speed, safety score, distance, duration, and Start Drive control.

2. **Live safety alerts on map**  
   Show route or map pins for speed, phone, harsh stop, or cornering alerts.

3. **Trip report detail**  
   Show completed trip map, score, alert breakdown, distance, duration, and top speed.

4. **Parent dashboard**  
   Show connected teen, live status, safety metrics, and recent trip list.

5. **QR pairing**  
   Show teen pairing QR and parent connection flow.

6. **Privacy & Safety**  
   Show in-app privacy/safety screen and account/data deletion access.

## Capture Notes

- Use realistic demo data, not a real teen's personal location history.
- Avoid showing private home/school addresses in map labels.
- Keep screenshots in light legal compliance: no claim that the app prevents crashes or guarantees safe driving.
- Do not show Dynamic Island marketing because Dynamic Island display was intentionally removed.
- Keep captions short if adding text overlays. Suggested captions:
  - "Live drive view"
  - "Safety alerts on the map"
  - "Trip reports families can review"
  - "Parent dashboard"
  - "Private QR pairing"
  - "Built-in privacy controls"

## Suggested File Names

- `iphone-01-drive-dashboard.png`
- `iphone-02-alert-map.png`
- `iphone-03-trip-report.png`
- `iphone-04-parent-dashboard.png`
- `iphone-05-qr-pairing.png`
- `iphone-06-privacy-safety.png`
- `ipad-01-drive-dashboard.png`
- `ipad-02-parent-dashboard.png`
- `ipad-03-trip-report.png`

## Before Upload

- Verify each screenshot has no simulator debug overlays.
- Verify battery/time/status bar look normal.
- Verify no real phone numbers, emails, exact home addresses, or live Firebase IDs are visible.
- Upload in App Store Connect while the app version is Prepare for Submission, Ready for Review, Invalid Binary, Rejected, Metadata Rejected, or Developer Rejected.
