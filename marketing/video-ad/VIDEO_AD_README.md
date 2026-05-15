# TeenDrive Video Ad

Created: 2026-05-12  
Creator: Vladimyr Merci

## Files

- `teendrive_video_ad.mp4` - finished 20-second vertical video ad.
- `teendrive_ad_source.gif` - animated preview/source fallback.
- `render_teendrive_ad.py` - renders the stylized ad frames and GIF.
- `MakeVideo.swift` - converts rendered PNG frames into MP4 using AVFoundation.
- `frames/` - generated PNG frame sequence used to build the MP4.

## Ad Concept

TeenDrive is shown as a calm, glass-themed family safety app:

1. Brand intro: "Teen Drive" and family driving awareness.
2. Safety alerts: speeding, harsh stop, phone, and night alerts on the map.
3. Parent connection: private QR pairing and parent dashboard.
4. Privacy close: privacy controls and account/data deletion.

## Compliance Notes

- Uses stylized product scenes, not private real teen location data.
- Avoids promising crash prevention or guaranteed safety.
- Describes TeenDrive as an awareness and coaching tool.
- Does not mention Dynamic Island because that feature was removed.

## Re-render

Run from the repo root:

```bash
/Users/vlad/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 marketing/video-ad/render_teendrive_ad.py
swift marketing/video-ad/MakeVideo.swift
```
