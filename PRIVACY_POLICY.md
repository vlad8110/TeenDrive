# TeenDrive Privacy Policy

Created: 2026-05-12  
Creator: Vladimyr Merci

TeenDrive is designed to help families review teen driving activity. The app stores the minimum information needed to show trips, safety alerts, pairing status, and parent notifications.

## Information Collected

- Account setup: role, display name, pairing codes, pairing tokens, family group IDs, teen profile IDs, and parent profile IDs.
- Driving activity: trip start and end times, route points, distance, top speed, speed-limit alerts, rapid acceleration alerts, harsh stop alerts, harsh cornering alerts, night driving alerts, phone-use alerts, and place-arrival alerts.
- Live drive status: current active-drive snapshot used by connected parents while a teen trip is active.
- Notification records: safety alert event data used to notify connected parents.
- Device sync data: Firebase Cloud Messaging token when Firebase notifications are enabled.

## How Data Is Used

- To show teen and parent dashboards, trip reports, safety scores, and map alerts.
- To sync teen trips to paired parents when Firebase is configured.
- To send parent notifications for important driving alerts.
- To keep deleted reports from reappearing after cloud sync.

## Where Data Is Stored

TeenDrive stores trip history locally on the device. When Firebase is configured, the app also stores selected account, trip, pairing, active-drive, and notification data in Firestore so paired family members can sync.

## Data Sharing

TeenDrive shares teen driving records only with parent accounts that have paired through the app's QR pairing flow. The app does not sell personal data.

## Account And Data Deletion

Users can open Profile > Privacy & Safety > Delete Account & Data to remove local account data and trip history from the device.

Teen deletion requests also remove synced teen trips, active-drive status, notification events, pairing tokens, teen profile records, and family teen records when Firebase rules permit the signed-in teen to delete them.

Parent deletion requests remove the parent profile and remove the parent link from connected teen records. Parent deletion does not delete a teen's driving history.

## Safety And Accuracy

Location, speed limit, phone-use, and motion events can be delayed, missing, or inaccurate because they depend on iOS permissions, GPS signal, sensor quality, network availability, and Apple platform behavior.

## Contact

For privacy questions or deletion support, contact the app owner or developer responsible for the TeenDrive deployment.
