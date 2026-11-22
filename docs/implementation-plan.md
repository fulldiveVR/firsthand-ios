# Implementation plan

Date: 2026-11-22. Status: draft, waiting for owner decisions (section 5).
Evidence for every technical claim is in [market-research.md](market-research.md).

## 1. Product

An iPhone AI that finds meaningful moments and suggests a camera-original photo to share with your approved friends, only when you say yes.

Core loop:

```
new photos in library
  -> on-device analysis (Vision), while charging and idle
  -> AI picks ONE moment per day (user cannot pick another)
  -> local notification "Your moment is ready"
  -> user: Share (Face ID) | Skip
  -> Share: post to own CloudKit zone, shared with approved friends
  -> friends get a push and see it in a calm, chronological feed
```

Positioning: Retro (weekly, friends-only, subscription) is the closest analog. Nobody found ships "AI picks, you only approve, friends only". The nearest product (PicSee) auto-sends after 24 hours. We never do that.

## 2. Fixed technical decisions

| ID | Decision | Reason |
|---|---|---|
| D1 | Never say "verified". Use "likely camera" or "unknown". Reference Image is an optional badge only. | Apple gives apps no verdict API. Reference Image needs iOS 27, iPhone 18 Pro, opt-in. |
| D2 | No own photo server. Each user owns one CloudKit zone, shared zone-wide with friends. | Apple hosts the data in the poster's iCloud. Owner does not want to store photos. |
| D3 | Full photo library access is required for the core loop. Limited access is a degraded mode with a re-ask. | With limited access the app sees only selected photos. |
| D4 | Background analysis uses `BGProcessingTask` with external power. Onboarding uses `BGContinuedProcessingTask` for the first scan. | Background time is not guaranteed. The first scan must not wait for a night. |
| D5 | Friendship = invite link (Messages, AirDrop, QR) + accept. Cap of 50 friends. | CloudKit cannot add a participant silently. Max 100 participants per share. |
| D6 | No auto-send, no like counts, no public profiles, no ads. | The product promise and the anti-doomscroll position. |
| D7 | No pulse or HealthKit. Sign in with Apple identifies the account. Face ID confirms the share. | HealthKit is not allowed for liveness. Biometrics give the app only a yes or no. |

## 3. Current draft (done)

- Repository with XcodeGen spec, SwiftUI app sources, and the `CandidCore` Swift package.
- `CandidCore`: models, protocols, moment scorer, suggestion engine (daily cap, cooldown, no repeats), resumable analysis queue, pipeline. 31 tests pass with `swift test`.
- App: onboarding, Sign in with Apple, Today card (Share / Skip), Feed, Friends, Settings. Adapters for PhotoKit, Vision, notifications, Face ID. CloudKit is a stub.
- Not verified: the iOS app has never been compiled for a device or run. This Mac has no Xcode.

## 4. Phases

| Phase | Goal | Work | Exit check |
|---|---|---|---|
| P1 Device bring-up (2-3 days) | The app runs on a real iPhone | Install Xcode 26. Set team and bundle id. Fix compile errors. Run Vision on 500+ real photos. Trigger the background task from the debugger. | App launches on device. Today shows a real suggestion. Background task completes and checkpoints. |
| P2 Moment engine v1 (1-2 weeks) | Picks that people would share | Score only new photos (library change observer). Tune weights on 3-5 real libraries. Add "new place", "people you meet", and burst/duplicate grouping. On-device caption with Foundation Models where available, none otherwise. | Owner rates 30 picks. At least 70% "I would share this". |
| P3 Sharing v1 (2 weeks) | Two friends share with each other | Custom zone, zone-wide `CKShare`, invite link and QR, accept flow, reverse share after accept, remove friend, delete post, feed from shared database. | Two devices with different Apple IDs exchange posts. Remove and delete work in both directions. |
| P4 Friend notifications (1 week, spike first) | Friends learn about a new post | Test `CKDatabaseSubscription` on the shared database with visible alert fields on real devices. If alerts are unreliable, add a stateless push relay that stores no photos. | 20 of 20 test posts produce a visible alert within 5 minutes, or the relay decision is made. |
| P5 Social loop (2 weeks) | People come back | Reciprocity gate (decide today's pick to see friends' picks, Skip counts). Home-screen widget with the latest friend post. Weekly recap. Gentle nudge when there was no new moment ("Go live a little"). | 10-person TestFlight group uses it for 2 weeks. Measure decide rate and D7. |
| P6 Beta release (1 week) | TestFlight external and App Review | Privacy nutrition label, purpose strings, App Review notes for full library access, account and data deletion, crash reporting without tracking. | Build approved for external TestFlight. |

Total: about 8-10 weeks for one iOS engineer.

## 5. Open decisions for the owner

| ID | Question | Recommendation |
|---|---|---|
| Q1 | Product name and bundle id. "Candid" is a codename. | Pick before P3, because CloudKit container ids cannot be renamed. |
| Q2 | Cadence: one pick per day or one per week? | Start with at most one per day, only when a good moment exists. Retro proves weekly works. Test both in P5. |
| Q3 | Minimum iOS version. The draft targets iOS 18. | iOS 26. It gives `BGContinuedProcessingTask` and Foundation Models, and by 2026-11 most active iPhones run it. |
| Q4 | Accept a tiny push relay (no photos, no feed) if CloudKit alerts fail in P4? | Yes. It is the only reliable way to send visible friend alerts. |
| Q5 | Business model. | Free core, later subscription for recaps and more friends, the same as Retro. No ads. |

## 6. Main risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | Apple Photos already curates on device for free. | Win on the friend loop and the nudge to go out, not on curation. |
| R2 | Many users refuse full library access. | Explain the value before the system prompt. Keep a working degraded mode. |
| R3 | Friend-only apps spike and then lose users (Lapse, Gas, BeReal). | Low cadence, no invite gates, widget as the main surface, measure D7/D30 early. |
| R4 | Every friendship needs iCloud on both sides and an accept step. | Simple QR and Messages invites. Show progress in the Friends screen. |
