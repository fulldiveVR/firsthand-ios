# Candid

An iPhone AI that finds meaningful moments and suggests a camera-original photo to share with your approved friends, only when you say yes.

Status: **draft**. Codename, may be renamed. CloudKit sharing is a stub.

## Docs

- [Implementation plan](docs/implementation-plan.md)
- [Market research](docs/market-research.md)

## Build

Requires Xcode 26 or later and an iPhone with iOS 18 or later.

```sh
brew install xcodegen && xcodegen generate
open Candid.xcodeproj
```

The `.xcodeproj` is generated and not committed. Set your own development team in Xcode, do not commit it.

Domain logic tests run on macOS without Xcode:

```sh
cd Packages/CandidCore && swift test
```

## Architecture

```
project.yml                 XcodeGen spec. App name and bundle id live here.
App/                        SwiftUI iOS app
  CandidApp.swift           entry point, BGTaskScheduler registration
  AnalysisScheduler.swift   BGProcessingTask: external power, no network
  AppModel.swift            UI state, Share (Face ID) and Skip
  AppServices.swift         wiring of real adapters, history file
  Adapters/                 PhotoKit, Vision, notifications, LocalAuthentication, CloudKit stub
  Views/                    Onboarding, Today, Feed, Friends, Settings
  Resources/                Info.plist, entitlements
Packages/CandidCore/        pure Swift package, tested on macOS
  Models.swift              PhotoCandidate, AnalysisSignals, ProvenanceStatus, Suggestion, Friend, Post
  Protocols.swift           PhotoLibrary, ImageAnalyzer, ShareService, FriendDirectory, Notifier, Clock
  MomentScorer.swift        deterministic scoring
  SuggestionEngine.swift    one suggestion, daily cap, cooldown, no repeats
  AnalysisQueue.swift       resumable queue with per-photo checkpoints
  SuggestionPipeline.swift  analyze, score, pick, notify
  Fakes.swift               in-memory ShareService and FriendDirectory
```

## Privacy principles

- Photos are analyzed on the device with Vision. No photo leaves the iPhone unless the user taps Share and confirms with Face ID or Touch ID.
- The app suggests one photo at a time. The user can only share it or skip it.
- Screenshots are excluded. Provenance is shown as "likely camera" or "unknown". The app never calls a photo "verified".
- Sharing goes to approved friends only, through CloudKit Sharing. Apple hosts the data. There is no own photo server.
- No ads, no tracking, no like counts. Settings deletes all local and shared data.

## License

MIT. See [LICENSE](LICENSE).
