# Firsthand design review and redesign spec

Date: 2026-11-22. Branch reviewed: `feat/onboarding-v2` (commit 9c4a2b7).
Target: iOS 26.0 deployment, built with the iOS 27.2 SDK.
Screenshots of the current build (temporary, not in the repo): `/private/tmp/claude-501/-Users-x0040h/4350e643-de2f-4c2f-8930-97f2dc5204ec/scratchpad/shots/` (onboarding `01-11`, `current-*.png`, `dark-*.png`).

Fixed product rules. The redesign must not break them.

- The AI picks one moment. The user can only Share or Skip. No photo picker, no "choose another".
- Face ID (or passcode fallback) confirms every share.
- Friends only, through CloudKit. No public profile, no follower counts, no like counts.
- Posts disappear after 30 days.
- Never say "verified". Provenance copy is "Likely original" or "Unknown".

---

## 1. Reference app

Primary reference: **Journal**.

Journal is the closest Apple app to Firsthand in job and in tone:

- Its core object is a *suggested moment* built on device from photos, places and people (Journaling Suggestions).
- The suggestion is a large photo card with a short title and context. The user accepts it or ignores it. Firsthand has the same accept/ignore shape.
- It is private by default and says so with calm, short copy and a privacy screen in onboarding.
- Its home is a single reverse-chronological timeline of rich cards with one prominent "+" action. It has no social graph chrome.
- It is visually quiet: system background, full-bleed photo cards with large corner radii, almost no color except the accent.

Secondary references and what to borrow:

| App | Borrow |
|---|---|
| Photos (iOS 26) | Featured photo hero at the top of a scroll view. Photo fills the card edge to edge, title and date sit on the photo with a scrim. Collections-style horizontal shelves for "Earlier". |
| Invites | Event card as a big poster: photo on top, background tint sampled from the photo, title in a large rounded or bold display style. Glass buttons on top of the photo. Clean onboarding with one hero card and one button. |
| Fitness (Sharing) | Friend list with one status line per friend. A separate "Awaiting Your Reply" section with an Accept button at the top. "+" in the toolbar to invite. Private reactions sent to one person, not public counts. |
| Find My (People) | Monogram avatars and one-line status. The share flow is a sheet that names the recipients and the duration before it sends. Firsthand's share sheet does the same with the audience and the 30-day expiry. |
| Wallet | Invite QR card as a real card object: rounded, tinted, with the QR in a white plate, like a boarding pass. |

---

## 2. Review of the current app

Findings are ordered by impact.

**Structure**

- **F1. Four tabs for two jobs.** Today shows at most one item per day. Feed is the only content that grows. Settings and Friends are rarely visited. A four-item tab bar makes a two-screen product look like an empty app. Apple apps of this size (Journal, Invites) use one main screen plus toolbar buttons.
- **F2. Today and Feed are split, so both feel empty.** Today is one card on a blank screen. Feed has no own moments in context and no link to today's suggestion. Journal shows the suggestion and the history in one timeline.
- **F3. Settings is a wall of static text.** Five privacy sentences render as a tall inset list with no controls. They read as a policy page, not as a privacy dashboard. The only control, "Delete All Data", sits under the tab bar at the bottom of the screen and is cut off (`current-settings.png`).

**Today**

- **F4. The suggestion card has no context.** It shows a photo, a caption and a provenance line. It does not say *when*, *where*, *with whom* or *why* the AI picked it. The user cannot judge the moment, so Share feels like a gamble. Journal always shows the date, place and the reason for the suggestion.
- **F5. Share and Skip are unbalanced and misaligned.** `frame(maxWidth:)` is applied after the button style, so the pills do not stretch. Skip is a small grey pill in the left half, Share a medium blue pill in the right half (`current-today-suggestion.png`). The Face ID glyph inside the Share button is the correct idea but looks like an emoji at that size.
- **F6. The share confirmation is a generic action sheet.** A `confirmationDialog` with "Share with Face ID" repeats the button the user just tapped. It does not show who receives the photo or how long it lives. That is the one moment where the app must show the audience.
- **F7. The empty Today is a form, not a state.** A small multicolor sun, a heavy title, two full-width buttons and a divider inside a grey card. It looks like a settings panel. "Find moments now" in bright prominent blue competes with the message that the user should go live their life.
- **F8. The analysis progress UI is a developer progress bar.** Phase name, percent, "37 of 120 photos analyzed" and a linear bar. Apple shows on-device work as a calm animated glyph with one short line (Photos "Analyzing", Journal "Preparing suggestions").

**Feed**

- **F9. The Feed is a plain List with system separators.** Separators cut between posts, insets do not match the photo width, and the name row looks like a mail list. It reads as a prototype, not as a photo app.
- **F10. Time copy is mechanical.** `Text(date, style: .relative)` renders "1 hr, 0 min" and "3 days, 1 hr". Apple uses "1h", "Yesterday", "Mon" in feeds.
- **F11. Every post repeats two grey lines.** "Likely taken with a camera" and "Disappears in 30 days" appear on every post at the same weight. They add noise and still do not make provenance understandable. Put provenance in Moment details and show expiry only when it is near (7 days or less).
- **F12. No avatars and no identity.** Posts and friends show only a name in text. Apple social surfaces (Fitness, Find My, Messages) always show a monogram or photo avatar.
- **F13. "Feed" is the wrong word.** It suggests an endless social feed. The product promise is the opposite.

**Friends**

- **F14. Invite actions dominate the screen.** Three blue rows ("Invite with Messages", "Show Invite QR Code", "Invite by Email or Phone") come before the friends. With friends, the list is pushed down. With no friends, "No friends yet." in a row is the whole empty state (`current-friends-empty.png`).
- **F15. Friendship states are jargon.** "You see their moments", "They see your moments", "Waiting for you to accept" and a "Share Back" button expose the two-share CloudKit model. The user thinks in "friend" or "pending".
- **F16. "Manage Sharing in iCloud" is a raw system escape hatch** shown as a main action. It belongs in a details screen.

**Onboarding**

- **F17. Illustrations are generic clip art.** Gradient discs, rings, blurred blobs and symbol badges look like a template. Each page has its own palette (orange, indigo, teal, red, green), so the app has no visual identity. Apple onboarding uses one hero visual in the app's own style and one accent color.
- **F18. Layout is top-heavy and left-aligned in a centered frame.** The page indicator sits top right next to a "Back" text button. Apple uses a centered welcome, a bottom-pinned button, and the system back chevron in the navigation bar.
- **F19. Copy is long.** Most pages have a large title, a three-line paragraph and three bullet rows. Several bullets repeat the paragraph. Apple pages carry one title, one sentence and at most three short feature rows on the welcome page only.

**Visual system**

- **F20. No Liquid Glass use beyond the default tab bar.** Buttons use `.bordered` / `.borderedProminent`, cards use opaque `secondarySystemBackground`. There is no glass control on top of photos, no scroll edge effect, no toolbar.
- **F21. Default blue accent and default typography.** Nothing signals "Firsthand". There is no app tint, no display type for moments, no consistent corner radius (12, 16, 20, 24 are all in use).

---

## 3. Principles

1. **One moment, one screen.** The home screen is the day's moment. Everything else is secondary and one tap away.
2. **The photo is the interface.** Photos are full-bleed and large. Chrome floats on top as glass. Text is short.
3. **Explain the pick.** Every suggestion says when, where and why. Trust comes from context, not from a badge.
4. **Private and calm.** No counts, no badges for attention, no red dots except a pending friend. Privacy facts are shown as live state, not as policy text.
5. **System first.** Use stock SwiftUI containers, system text styles, SF Symbols and Liquid Glass. Custom drawing only for the moment card and the onboarding hero.

---

## 4. Navigation model

Recommendation: **one main screen ("Moments") with a toolbar, no tab bar.**

```
App
└─ NavigationStack  "Moments"            (home, large title)
   ├─ toolbar leading:  Friends button   (person.2)        → Friends sheet
   ├─ toolbar trailing: Profile button   (avatar monogram) → Profile & Privacy sheet
   ├─ section: Today                     (hero card or state card)
   ├─ section: Friends' moments          (cards, newest first)
   ├─ section: Your moments              (horizontal shelf, last 30 days)
   └─ push: Moment details               (zoom transition from any card)
```

Why:

- The app has one recurring job: look at today's moment, decide, then look at friends' moments. Both fit in one vertical scroll (F1, F2). Journal works the same way.
- A tab bar with four items for this little content makes every tab look empty. Removing it gives the photo the full height.
- Friends is a management task done a few times a month. A sheet keeps the home in place, like Journal's settings or Invites' "Shared with you".
- Profile in the trailing toolbar is the iOS 26 pattern for account and settings (App Store, Music, Podcasts, Invites).
- The 30-day horizon makes "your moments" small (max 30 items). A horizontal shelf is enough.

Alternative if the owner wants tabs: two tabs, "Moments" and "Friends", with Profile in the toolbar. Do not keep four tabs.

Deep links and notifications:

- "A moment is ready" opens Moments scrolled to top.
- "Mia shared a moment" opens Moment details for that post.
- Invite link acceptance shows the Friends sheet with the new friend highlighted.

---

## 5. Screens

Notation: indented component tree. `[glass]` marks Liquid Glass. Symbols are SF Symbols names.

### 5.1 Moments (home)

```
NavigationStack
└─ ScrollView (.scrollEdgeEffectStyle(.soft, for: .top))
   ├─ TodaySection
   │  ├─ header: "Today" + date subtitle ("Saturday, November 22")
   │  └─ one of: MomentHeroCard | AnalyzingCard | QuietDayCard | DecidedCard | LimitedAccessCard
   ├─ FriendsMomentsSection  (header "From Friends")
   │  └─ LazyVStack of FriendMomentCard  | FriendsEmptyCard
   └─ YourMomentsShelf       (header "Your Moments", only if count > 0)
      └─ ScrollView(.horizontal) of MomentThumb (3:4, 120pt wide)
toolbar
├─ .topBarLeading:  Button(Friends, systemImage: "person.2")   [glass, default]
└─ .topBarTrailing: ProfileButton (monogram avatar 32pt)       [glass, default]
```

Title: large title "Moments". Background: `systemBackground`, so photos sit on white or black like Photos and Journal. Use one scroll edge effect per view (HIG). In iOS 27 the system draws a uniform top toolbar when content scrolls under it. Do not add a custom header background.

#### Today states

| State | Component | Content |
|---|---|---|
| Suggestion ready | `MomentHeroCard` | See below. |
| Analyzing (first scan or "Find moments now") | `AnalyzingCard` | 4:5 card, soft animated gradient sampled from accent. Center glyph `sparkle.magnifyingglass` with `.symbolEffect(.pulse)` (Reduce Motion: static). Title "Looking at your recent photos". Subtitle "On this iPhone. You can leave the app." Small `ProgressView(value:)` as a thin 4pt capsule only in the `.analyzing` phase. Button "Stop" `.buttonStyle(.glass)`. No percent text. |
| No moment yet today | `QuietDayCard` | Compact card, 16pt padding. Symbol `leaf` (hierarchical, accent). Title "Nothing stood out yet". Body "Go live a little. We'll tell you when a moment stands out." Secondary text button "Look now" (`.buttonStyle(.glass)`, small). This replaces the big blue "Find moments now" (F7). |
| Shared today | `DecidedCard(.shared)` | Small version of the hero (photo thumb 64pt, rounded 12) + "Shared with 4 friends" + "Disappears Dec 22" + chevron → Moment details. Symbol `checkmark.circle.fill` green. |
| Skipped today | `DecidedCard(.skipped)` | One line, secondary: "You skipped today's moment. Next one tomorrow." Symbol `moon.zzz`. No undo (the moment is gone by rule). |
| Limited or denied photo access | `LimitedAccessCard` | Symbol `photo.badge.exclamationmark` orange. Title "Firsthand can't find new moments". Body "It can only see the photos you selected." Button "Allow Full Access" `.glassProminent` → system Settings. |
| Error during analysis | inline in `AnalyzingCard` | Replace title with "Couldn't finish looking" and the button with "Try Again". No error codes. |

#### MomentHeroCard (the key component)

```
ZStack(alignment: .bottom)                       RoundedRectangle(32, .continuous) clip
├─ Image(photo).resizable().scaledToFill()       aspect 4:5, full width minus 16pt margins
├─ LinearGradient scrim (clear → black 55%)      bottom 45% only
└─ VStack(alignment: .leading, spacing: 12)      padding 20
   ├─ Text(caption)                              .title2.bold(), white, 2 lines max
   ├─ Text("Today at 6:40 PM · Near Lake Merritt") .subheadline, white 85%
   ├─ ReasonChips (HStack, wraps)                each chip [glass .clear] capsule
   │    e.g. "New place" mappin.and.ellipse · "With friends" person.2.fill ·
   │         "Golden hour" sun.horizon.fill · "Likely original" camera.fill
   └─ GlassEffectContainer(spacing: 12) HStack
      ├─ Button("Skip")  .buttonStyle(.glass)        flexible width, .controlSize(.large)
      └─ Button("Share", systemImage: "faceid") .buttonStyle(.glassProminent)  flexible width
Overlay top-trailing: Button(systemImage: "info") [glass] → Moment details
```

- The two buttons have equal width (`frame(maxWidth: .infinity)` *inside* the label) (F5).
- Chips come from the scorer signals. Persist them on `Suggestion` as `reasons: [MomentReason]` (new Core field). Map: newPlace → "New place", faceCount ≥ 2 → "With friends", faceCount == 1 → "With someone", rewarded scene label → the label in title case ("Beach", "Sunset", "Food"), recency < 24 h → "Today", provenance → "Likely original" or "Unknown" (never "verified").
- Show at most 3 chips. Provenance chip always last.
- Tap on the photo → Moment details (zoom transition).
- Long press → context menu: "Moment Details", "Skip". No "pick another".

Motion: card appears with `.transition(.scale(0.96).combined(with: .opacity))`. After Share succeeds, the hero morphs into `DecidedCard` with `matchedGeometryEffect` on the image and a `.symbolEffect(.drawOn)` checkmark. After Skip, the card slides down and fades (Reduce Motion: cross-fade only).

#### FriendMomentCard

```
VStack(alignment: .leading, spacing: 10)
├─ HStack: Avatar(28) · Text(name).headline · Spacer · Text(shortTime).footnote.secondary
├─ Image(photo) 4:5 or native aspect clamped 4:5…1:1, RoundedRectangle(24)
├─ Text(caption).body (if any)
└─ if daysLeft <= 7: Label("Disappears in 3 days", systemImage: "hourglass").footnote.secondary
```

- No List, no separators. 28pt vertical spacing between cards (F9).
- Short time format: "Now", "12m", "3h", "Yesterday", weekday name for < 7 days, else "Nov 12". Implement with `Date.RelativeFormatStyle(presentation: .named, unitsStyle: .abbreviated)` for < 24 h and `Date.FormatStyle` weekday otherwise (F10).
- Provenance is not shown on the card. It is in Moment details (F11).
- Own posts appear in "Your Moments", not here. The feed section shows friends only.
- Context menu on a friend card: "Moment Details", "Mute Mia" (optional, later). On own thumbs: "Delete…" (destructive, confirmation).
- Optional (mark as later): **private reaction**. A glass button with `face.smiling` opens 5 fixed emoji. The reaction goes only to the author. The author sees "Mia reacted 😊" in Moment details. No counts anywhere. Skip in v1 unless the owner asks.

Empty state when no friends: `FriendsEmptyCard` with three overlapping monogram circles (grey), title "Moments are better with friends", body "Only people you invite can see what you share.", button "Invite Friends" `.glassProminent` → Friends sheet.
Empty state with friends but no posts: one line "No moments from friends in the last 30 days." in secondary.

### 5.2 Share sheet (replaces the confirmation dialog, F6)

Presented with `.sheet` at `.presentationDetents([.medium])`. In iOS 26 a partial-height sheet gets the glass background by default. Do not set a custom background.

```
NavigationStack
└─ VStack(spacing: 20) padding 20
   ├─ HStack: photo thumb 72pt (rounded 16) · VStack(caption.headline, "Today · Near Lake Merritt".subheadline.secondary)
   ├─ AudienceRow: overlapping avatars (max 5, +N) · "Your 4 friends"            symbol person.2.fill
   ├─ ExpiryRow:   "Visible until December 22" · "Then it's deleted from iCloud" symbol hourglass
   ├─ PrivacyRow:  "Only the photo and caption are shared. No location."         symbol lock.fill
   └─ Button { Label("Share with Face ID", systemImage: "faceid") } .glassProminent, full width, .large
toolbar: .cancellationAction  Button(role: .cancel)   (iOS 26 shows an xmark glass button)
```

- Caption: shown, not editable in v1 (rule: the AI suggests, the user approves). If editing is added later, use a single-line `TextField` with `axis: .vertical`.
- Pending friends (invited, not accepted) are not counted in the audience.
- If the audience is 0: the sheet replaces the Share button with "Invite a Friend First" → Friends sheet.
- States: idle, authenticating (button shows `ProgressView`), success (sheet dismisses, home plays the hero → DecidedCard morph, `.sensoryFeedback(.success, trigger:)`), failure (inline red footnote above the button: "Couldn't share. Check your connection and try again.").

### 5.3 Moment details

Pushed with `.navigationTransition(.zoom(sourceID: id, in: ns))` from any card, source marked with `.matchedTransitionSource(id:in:)`.

```
ScrollView
├─ Image(photo) full width, native aspect, .backgroundExtensionEffect() under the nav bar
├─ VStack(alignment: .leading, spacing: 16) padding 20
│  ├─ Text(caption).title2.bold
│  ├─ Text(author · "Saturday, November 22 at 6:40 PM").subheadline.secondary
│  ├─ GroupBox "Why this moment" (own suggestion only)
│  │    rows of Label(reason, systemImage:) from MomentReason
│  ├─ GroupBox "Place"   (own only) Text("Near Lake Merritt") — coarse, never coordinates or a map pin
│  ├─ GroupBox "Origin"
│  │    Label("Likely original", systemImage: "camera.fill")  + footnote:
│  │    "The photo has camera data and is not a screenshot or an edited copy. Firsthand can't prove where a photo came from."
│  │    or Label("Unknown", systemImage: "questionmark.circle") + "Firsthand found no camera data for this photo."
│  │    or (iOS 27 reference data) Label("Likely original", systemImage: "camera.badge.checkmark") — still never "verified"
│  └─ GroupBox "Visibility"  "Visible to your 4 friends until December 22" (own) / "Disappears in 12 days" (friend's)
toolbar
├─ own post: Menu(systemImage: "ellipsis") { Button("Delete Moment", role: .destructive) }
└─ friend post: none
```

Place copy: reverse-geocode the coarse bucket center to a neighborhood or city. Use `MKReverseGeocodingRequest` if it is available on iOS 26, else `CLGeocoder` (check the deprecation state in the 27.2 SDK). Show "Near …". If geocoding fails, omit the row. Note: reverse geocoding sends the coarse coordinate to Apple Maps. State this in the privacy copy, or skip the place row for strict on-device mode.

### 5.4 Friends (sheet)

Presented as a large sheet (`.presentationDetents([.large])`) with its own NavigationStack, title "Friends", inline display.

```
NavigationStack
└─ List(.insetGrouped)
   ├─ Section (no header)  InviteCard                       ← top, compact
   │    HStack: QR glyph tile 56pt (qrcode, white plate) · VStack("Invite a Friend".headline, "They need iPhone and iCloud.".footnote)
   │    HStack: ShareLink "Message" [glass] · Button "Show QR Code" [glass]
   ├─ Section "Waiting" (only if any)
   │    FriendRow(pending) … trailing Text("Invited").secondary   swipe: "Cancel Invite"
   │    FriendRow(needs accept) … trailing Button("Accept") .glassProminent .small
   ├─ Section "Friends"  footer: "4 of 50"
   │    FriendRow: Avatar(40) · name · subtitle "Shared 2 days ago" or "No moments yet"
   │    swipe: "Remove" (destructive, confirmation)
   └─ Section  NavigationLink "Sharing Details" → iCloud management (UICloudSharingController), "Invite by Email or Phone"
toolbar .confirmationAction: Button("Done")  (glass, default)
```

- Friendship states map to two user words (F15): **Friend** (mutual or one-way) and **Waiting**. One-way incoming ("needs reverse share") is fixed automatically: when the user accepts an invite, the app creates the reverse share in the same flow and shows the invite link sheet. The "Share Back" button goes away from the list. If automation is not possible, the row says "Finish adding Mia" with a button "Finish".
- Empty state (no friends, nothing waiting): `ContentUnavailableView` with symbol `person.2`, title "Add your first friend", description "Only people you invite can see what you share. Up to 50 friends.", actions: "Message an Invite" (`.glassProminent`), "Show QR Code" (`.glass`) (F14).
- QR code sheet: Wallet-style card. Rounded 28pt card, accent-tinted gradient top band with app glyph and "Firsthand", white plate with the QR (240pt), name of the inviter, line "Scan with the iPhone camera. Works for one person." Buttons below the card: "Send Link" (`ShareLink`, `.glassProminent`), "Done" in toolbar.
- Avatar: monogram from the CloudKit display name in a circle with a color derived from a stable hash of the friend ID (system colors only: blue, green, orange, pink, purple, teal, indigo). Font `.headline` rounded. No photos in v1.

### 5.5 Profile & Privacy (sheet, replaces Settings, F3)

Opened from the toolbar avatar. Large sheet, NavigationStack, title "Profile" inline.

```
List(.insetGrouped)
├─ Header (no section chrome): Avatar(72) centered · name.title2.bold · "Signed in with Apple".footnote.secondary
├─ Section "Privacy"
│  ├─ PrivacyStatRow  iphone            "On-device analysis"    trailing "On" badge (green capsule)
│  ├─ PrivacyStatRow  photo.on.rectangle "Photos analyzed"       trailing "1,284"   footer-like subtitle "Last 30 days"
│  ├─ PrivacyStatRow  square.and.arrow.up "Moments shared"       trailing "6"
│  ├─ PrivacyStatRow  icloud            "Stored in your iCloud" trailing "6 photos · 14 MB"
│  └─ PrivacyStatRow  hourglass         "Oldest disappears"     trailing "Dec 2"
│  footer: "Photos never leave this iPhone unless you share them. No ads, no tracking, no Firsthand photo server."
├─ Section "Moments"
│  ├─ Button "Look for a Moment Now"  (shows AnalyzingCard state on home, then dismisses)
│  ├─ NavigationLink "Photo Access" → trailing "Full" / "Limited" (opens system Settings)
│  └─ NavigationLink "Notifications" → trailing "On" / "Off"
├─ Section "About"
│  └─ links: Privacy Policy, Terms, Version
└─ Section
   └─ Button("Delete All Data", role: .destructive)
      footer: "Removes suggestions, analysis, everything you shared and your friend connections. Your photo library is not changed."
```

- "Photos analyzed" comes from `AnalysisCache` count. "Stored in your iCloud" from own posts. These numbers make the privacy promise visible instead of stating it five times.
- Delete All Data uses a two-step confirmation: `confirmationDialog` then a destructive alert "This can't be undone."

### 5.6 Onboarding (keep 8 steps, F17-F19)

Structure per page, same for all pages:

```
VStack
├─ Spacer
├─ HeroVisual (max 280pt tall, centered)
├─ Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
├─ Text(body).font(.body).foregroundStyle(.secondary).center, max 2 sentences
├─ (welcome only) FeatureRows ×3, left aligned, symbol 28pt accent hierarchical
├─ Spacer
└─ bottom safeAreaBar: primary Button .glassProminent .large full width
                       optional secondary Button .plain ("Not Now")
Navigation: NavigationStack with system back button. No custom "Back". Page dots: none (Apple onboarding does not show dots for flows with permission prompts).
```

Visual direction: one style for all heroes. Use **real-looking photo cards** (bundled sample photos, 3 to 4 licensed images) arranged as a fanned stack, like the Invites and Journal welcome screens. Never gradient-with-symbol tiles. One accent color for the whole flow.

| # | Page | Hero | Title | Body | Button |
|---|---|---|---|---|---|
| 1 | Welcome | 3 photo cards fanned, center card has a glass "Today" chip, slow parallax float | Firsthand | One real moment a day, shared only with friends, only when you say yes. | Continue |
| 2 | How it works | Hero card with glass Skip / Share buttons; Share pulses once | You just say yes or no | Firsthand picks one moment from your recent photos. You never scroll or choose. | Continue |
| 3 | Privacy | Photo card with an `iphone` glass badge and `lock.fill`, draw-on animation | Stays on your iPhone | Photos are analyzed on device. Nothing leaves without Face ID. | Continue |
| 4 | Photos | Grid of 6 small photo tiles with a scan shimmer | Allow access to recent photos | Firsthand needs full access to find new moments. | Allow Photo Access (then system prompt). Limited/denied states keep current logic. |
| 5 | Notifications | Lock screen notification mock in glass: "A moment is ready" | Know when a moment is ready | At most once a day. Never shows the photo. | Turn On Notifications / Not Now |
| 6 | Friends | 3 monogram avatars around a card, hourglass chip "30 days" | Friends only. Gone in 30 days. | Share with up to 50 people you invite. Every moment disappears after 30 days. | Continue |
| 7 | Sign in | App glyph | Sign in with Apple | Friends see only the name you choose. | `SignInWithAppleButton` (style follows color scheme) |
| 8 | First scan | `AnalyzingCard` itself, live | Finding your first moment | You can leave the app. We'll let you know. | none while scanning; "Continue" when done |

Motion: page change uses the NavigationStack push. Hero elements use `.symbolEffect(.drawOn)` and `PhaseAnimator` once per appearance, not looping forever. Reduce Motion: static hero, cross-fade push.

---

## 6. Visual system

### Color

- **Accent:** one custom tint, warm coral "Firsthand Sunrise". Light `#F2603A`, dark `#FF7A52`. Define as an asset color `AccentColor` with light/dark and high-contrast variants. Use it for the prominent glass button tint, selected states and symbol accents only.
- **Backgrounds:** `systemBackground` for home and details. `systemGroupedBackground` for Friends and Profile lists. No custom grey cards (F21).
- **Card surfaces on home:** non-photo cards (Quiet day, Analyzing, Empty friends) use `.background(.fill.quaternary, in: shape)` in light and `secondarySystemBackground` in dark. Not glass: glass is for controls, not for content (HIG).
- **On-photo controls:** Liquid Glass `.clear` variant for chips over photos, `.regular` for buttons, `.glassProminent` with the accent for Share.
- **Status colors:** system green (shared, on), orange (limited), red (destructive only).

### Typography (system styles only, SF Pro)

| Use | Style |
|---|---|
| Home title | `.largeTitle` via navigation title |
| Section headers on home | `.title3.bold()` |
| Hero caption | `.title2.bold()` (on photo, white) |
| Card name / list primary | `.headline` |
| Meta line (time, place) | `.subheadline`, secondary |
| Chips | `.footnote.weight(.semibold)` |
| Footnotes, expiry | `.footnote`, secondary |
| Onboarding titles | `.largeTitle.bold()` centered |
| Monogram avatars | `.system(.headline, design: .rounded)` |

Do not use fixed font sizes. Replace `.font(.system(size: 40))` (empty Today) with `.imageScale(.large)` + `.font(.largeTitle)`.

### Shape and spacing

| Token | Value |
|---|---|
| Hero card radius | 32, `.continuous` (matches iOS 26 large concentric corners) |
| Feed photo radius | 24 |
| Small thumb radius | 12 |
| Chip | `Capsule()` |
| Screen margin | 16 (20 on Max sizes via `.contentMargins`) |
| Card inner padding | 20 |
| Space between cards | 28 |
| Space between sections | 36 |

Use `ConcentricRectangle` / `.containerShape` where a glass button sits inside the hero card corner (iOS 26).

### Dark mode

Photos stay unchanged. Scrims stay black. Non-photo cards switch to `secondarySystemBackground`. Accent uses the dark variant. Check the coral on glass in both modes for 4.5:1 contrast of white label text.

### Accessibility

- Dynamic Type: hero caption and chips wrap. At accessibility sizes, chips stack vertically and the Share/Skip buttons stack (Share on top). Use `ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`.
- VoiceOver: the hero card is one element with label "Suggested moment. Golden hour at the lake. Today at 6:40 PM near Lake Merritt. New place, with friends, likely original." Actions: "Share", "Skip", "Details" via `.accessibilityAction`.
- Reduce Motion: no parallax, no pulsing, cross-fades only.
- Reduce Transparency: the system makes glass more opaque. Also replace the photo scrim text with a solid `regularMaterial` panel when `accessibilityReduceTransparency` is true.
- Increase Contrast: use `colorSchemeContrast == .increased` to raise scrim opacity to 70% and add a 1pt border on chips.
- Minimum hit target 44×44 for all chips that are tappable (chips are not tappable in v1).

---

## 7. Implementation notes

### API map

Deployment target is iOS 26.0. Everything in the first table is available without checks. Source: Apple SwiftUI documentation updates (https://developer.apple.com/documentation/updates/swiftui).

| Component | API | Min iOS |
|---|---|---|
| Skip / Share on hero, Stop, Look now | `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` + `.tint(.accentColor)` | 26.0 |
| Skip + Share pair (morph and shared glass) | `GlassEffectContainer(spacing:)` | 26.0 |
| Reason chips on photo | `.glassEffect(.clear, in: .capsule)` over a dark scrim (HIG: `.clear` only over rich media, dim bright media about 35%) | 26.0 |
| Info button on hero | `Button(...).buttonStyle(.glass)` + `.buttonBorderShape(.circle)` | 26.0 |
| Hero → DecidedCard morph | `glassEffectID(_:in:)`, `glassEffectTransition(_:)`, `matchedGeometryEffect` | 26.0 |
| Toolbar buttons (Friends, Profile) | stock `ToolbarItem`, glass is automatic. Avatar: `.sharedBackgroundVisibility(.hidden)` so the monogram circle is not inside a second glass capsule | 26.0 |
| Spacing between toolbar groups | `ToolbarSpacer(.fixed)` | 26.0 |
| Home top edge | `.scrollEdgeEffectStyle(.soft, for: .top)` | 26.0 |
| Moment details photo under nav bar | `.backgroundExtensionEffect()` | 26.0 |
| Onboarding bottom buttons | `.safeAreaBar(edge: .bottom) { ... }` | 26.0 |
| Card → details | `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))` | 18.0 |
| Share sheet | `.sheet` + `.presentationDetents([.medium])`, no custom background (iOS 26 glass sheet) | 16.0 |
| Share success haptic | `.sensoryFeedback(.success, trigger:)` | 17.0 |
| Checkmark, lock, scan glyphs | `.symbolEffect(.drawOn)`, `.symbolEffect(.pulse)`; `.symbolColorRenderingMode(.gradient)` for onboarding hero glyphs | 26.0 (drawOn, gradient), 17.0 (pulse) |
| Analysis progress glyph | `.symbolVariableValueMode(.draw)` with `Image(systemName:variableValue:)` | 26.0 |
| Empty states | `ContentUnavailableView` | 17.0 |
| Accessibility branches | `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityReduceMotion`, `accessibilityDifferentiateWithoutColor` | 13.0 |

Not used, on purpose:

- `tabBarMinimizeBehavior`, `tabViewBottomAccessory`, `Tab(role: .search)` (26.0). The recommended model has no tab bar. If the owner keeps two tabs, add `.tabBarMinimizeBehavior(.onScrollDown)` on Moments.
- Custom glass on cards. HIG puts glass in the control layer only.

iOS 27 additions (SDK 27.2). Each needs `if #available(iOS 27, *)` with an iOS 26 fallback. Source: WWDC26 session 269 (https://developer.apple.com/videos/play/wwdc2026/269/).

| API | Use in Firsthand | Fallback on 26 |
|---|---|---|
| `Tab(role: .prominent)` | Only in the two-tab alternative: Moments as the prominent tab. | normal `Tab` |
| `swipeActionsContainer()` + `swipeActions(...)` outside `List` | Delete on own moment thumbs in the shelf. | context menu |
| `toolbarMinimizationBehavior(_:for:)` | Let the toolbar shrink while scrolling friends' moments. | none |
| `ToolbarItemPlacement.topBarPinnedTrailing` | Keep the Profile avatar visible when the toolbar compacts. | `.topBarTrailing` |
| `NavigationTransition.crossFade` | Reduce Motion variant of the card → details transition. | `.automatic` |

Glass appearance in iOS 27 changes without a recompile (more diffusion, darker edge, brighter highlight). The user can set glass from "ultra clear" to "fully tinted" in Settings. No public API reads that value. Test every glass control over bright and dark photos at both ends of that slider.

### Build order (one implementation agent)

Each step builds, keeps tests green, and is screenshot-checked with DEBUG demo content.

- **D1. Debug demo content.** Add `-demoContent`, `-demoState <suggestion|analyzing|quiet|shared|skipped|limited>` launch arguments (DEBUG only) with fixture photos in a debug asset catalog. Needed for every later screenshot.
- **D2. Design tokens.** `AccentColor` asset, `Theme` enum with radii and spacing, `Avatar` view (monogram + stable color), short relative time formatter with tests.
- **D3. Core: `MomentReason`.** Add `reasons: [MomentReason]` to `Suggestion` (Codable with default `[]` for old data). Fill it in `SuggestionEngine` from scorer signals. Unit tests for the mapping. Provenance labels: "Likely original" / "Unknown".
- **D4. Navigation shell.** Replace `TabView` with `NavigationStack` "Moments" + toolbar Friends and Profile buttons. Move current Friends and Settings content into sheets unchanged. Keep alerts and invite sheet.
- **D5. MomentHeroCard + Today states.** Hero card with scrim, chips, glass Skip/Share, info button. AnalyzingCard, QuietDayCard, DecidedCard, LimitedAccessCard. Remove `FindMomentsPanel` from Today.
- **D6. Share sheet.** Replace the confirmation dialog with the medium-detent sheet. Face ID runs on the sheet button. Success morph and haptic.
- **D7. Friends' moments section and Your Moments shelf.** Card layout, short time, expiry only ≤ 7 days, empty states, delete via context menu on own thumbs.
- **D8. Moment details.** Zoom transition, why/place/origin/visibility groups, on-device reverse geocode of the bucket.
- **D9. Friends sheet.** Invite card, Waiting and Friends sections, simplified states, auto reverse share, empty state, Wallet-style QR card.
- **D10. Profile & Privacy sheet.** Stats rows from AnalysisCache and own posts, Photo Access and Notifications rows, two-step delete.
- **D11. Onboarding visuals.** NavigationStack-based pages, centered layout, bottom `safeAreaBar` buttons, photo-card heroes, single accent, shorter copy. Keep the 8 steps and all permission logic.
- **D12. Accessibility and polish pass.** Dynamic Type XXXL and AX5, VoiceOver labels and actions, Reduce Motion, Reduce Transparency, Increase Contrast, dark mode screenshots of every screen.

---

## 8. Research sources

- Apple, What's new in design (HIG change log, 2026-06-08 and 2026-09-09): https://developer.apple.com/design/whats-new/
- HIG Materials (Liquid Glass): https://developer.apple.com/design/human-interface-guidelines/materials
- Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- SwiftUI updates and API availability: https://developer.apple.com/documentation/updates/swiftui
- WWDC25 356, Get to know the new design system: https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC26 269, What's new in SwiftUI: https://developer.apple.com/videos/play/wwdc2026/269/
- SF Symbols 7 and 8: https://developer.apple.com/sf-symbols/
- iOS 27 Liquid Glass changes: https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/ , https://siliconangle.com/2026/06/08/apple-refines-liquid-glass-design-expands-child-safety-tools-wwdc/
- Journal: https://apps.apple.com/app/journal/id6447391597 , https://9to5mac.com/2025/06/17/apples-journal-app-is-coming-to-ipad-and-mac-with-big-upgrades/
- Photos in iOS 26: https://techcrunch.com/2025/06/09/apple-brings-back-tabs-to-the-photos-app-in-ios-26 , https://macrumors.com/guide/ios-26-photos-app
- Apple Invites: https://apple.com/newsroom/2025/02/introducing-apple-invites-a-new-app-that-brings-people-together
- Fitness Sharing: https://www.macrumors.com/how-to/share-activity-friends-apple-watch/ , https://support.apple.com/en-is/guide/watch/apd68a69f5c7

Not verified from a source (from memory, check on a device before relying on them): Journal's Recommended/Recent suggestion segments and card layout, Photos Featured Photos layout, Invites image-derived card tint, Wallet card stack details.

HIG note for the AI pick: the 2026-06-08 HIG adds Generative AI guidance on feedback and refinement. Treat Skip as the feedback signal. Do not add a "show me another" control, because the product rule forbids it.
