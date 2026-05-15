# Privacy Nutrition Label Draft

Created: 2026-05-12  
Creator: Vladimyr Merci

This is the draft App Store Connect privacy questionnaire for the current TeenDrive app. Confirm it against the exact production Firebase configuration, SDK list, and any analytics/crash tooling added later.

## Tracking

Does the app use data to track users across apps or websites owned by other companies?

Recommended answer: No.

Reason: TeenDrive does not include advertising, third-party ad attribution, cross-app tracking, or data broker sharing in the current codebase.

## Data Linked To The User

TeenDrive uses Firebase anonymous authentication and family pairing records. Treat the following as linked to the user because they are connected to a Firebase user ID, teen profile, parent profile, or family group.

### Location

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Precise location route points.
- Current active-drive location.
- Alert coordinates.

### Identifiers

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Firebase anonymous auth UID.
- Teen profile ID.
- Parent profile ID.
- Family group ID.
- Firebase Cloud Messaging token.

### Contact Info

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Display name entered for teen or parent.

Note: The app does not currently collect email address, phone number, or physical address.

### User Content

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Saved place names and coordinates if the user configures place alerts.

### Usage Data

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Completed trip summaries.
- Distance.
- Duration.
- Top speed.
- Safety score.
- Safety alert counts.
- Active-drive state.

### Other Data

Collects: Yes  
Linked to user: Yes  
Used for: App Functionality

Data examples:

- Rapid acceleration alerts.
- Harsh stop alerts.
- Harsh cornering alerts.
- Night driving alerts.
- Phone opened/unlocked while driving alerts.
- Speed-over-limit alerts.
- Notification event records.

## Data Not Currently Collected By App Code

Based on the current repo, TeenDrive does not intentionally collect:

- Purchases.
- Financial information.
- Health and fitness data.
- Contacts.
- Browsing history.
- Search history.
- Advertising data.
- Emails or text messages.
- Photos, videos, or audio.
- Crash logs through Crashlytics.

## Third-Party SDK Notes

Firebase SDKs are included for:

- Firebase Auth.
- Firebase Firestore.
- Firebase Messaging.
- Firebase Core.

Do not add Firebase Analytics, Crashlytics, Performance Monitoring, or other SDKs without updating this privacy label draft.

## App Store Connect Checklist

- Set tracking to No.
- Mark all collected data above as linked to the user.
- Set purposes to App Functionality.
- Do not mark data as used for third-party advertising or developer advertising unless that changes.
- Update the public privacy policy URL before submission.
