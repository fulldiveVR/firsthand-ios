#if os(iOS)
import FirsthandCore
import SwiftUI

/// The Today section of the home screen. Shows exactly one state.
/// The AI picks the moment. The user can only Share or Skip it. There is no photo picker.
struct TodaySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph
    var onDetails: (Suggestion) -> Void = { _ in }
    var onShare: (Suggestion) -> Void = { _ in }

    enum Mode: Equatable {
        case suggestion(Suggestion)
        case analyzing(AnalysisProgress?)
        case failed
        case decided(Suggestion)
        case limited
        case quiet
    }

    var mode: Mode {
        if let pending = model.pending { return .suggestion(pending) }
        switch model.manualScan {
        case .running(let progress): return .analyzing(progress)
        case .finished(.failed): return .failed
        case .finished(.needsFullAccess): return .limited
        default: break
        }
        if model.photoAccess.isDegraded { return .limited }
        if let decided = model.decidedToday { return .decided(decided) }
        return .quiet
    }

    var body: some View {
        let mode = mode
        Group {
            switch mode {
            case .suggestion(let suggestion):
                MomentHeroCard(
                    suggestion: suggestion,
                    namespace: morph,
                    onShare: { onShare(suggestion) },
                    onSkip: { skip() },
                    onDetails: { onDetails(suggestion) }
                )
                .momentTransitionSource(MomentRoute.suggestion(suggestion).id)
                .transition(heroTransition)
                .task(id: suggestion.id) { await model.resolvePlace(for: suggestion) }
            case .analyzing(let progress):
                AnalyzingCard(progress: progress, failed: false, onStop: model.cancelFindMoments, onRetry: model.findMomentsNow)
                    .transition(cardTransition)
            case .failed:
                AnalyzingCard(progress: nil, failed: true, onStop: {}, onRetry: model.findMomentsNow)
                    .transition(cardTransition)
            case .decided(let suggestion):
                DecidedCard(suggestion: suggestion, namespace: morph, onDetails: { onDetails(suggestion) })
                    .momentTransitionSource(MomentRoute.suggestion(suggestion).id)
                    .transition(cardTransition)
            case .limited:
                LimitedAccessCard()
                    .transition(cardTransition)
            case .quiet:
                QuietDayCard()
                    .transition(cardTransition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.45), value: mode)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    /// Appears with a slight scale. After Skip it slides down and fades.
    private var heroTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    private func skip() {
        Task { await model.skip() }
    }
}

// MARK: Hero

/// Today's moment: a full-bleed photo with its caption, when and where, the reasons, and Skip / Share.
struct MomentHeroCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let suggestion: Suggestion
    var namespace: Namespace.ID
    var onShare: () -> Void
    var onSkip: () -> Void
    var onDetails: () -> Void

    var body: some View {
        MomentPhoto(assetID: suggestion.assetID, side: 1400)
            .matchedGeometryEffect(id: MorphID.photo, in: namespace)
            .aspectRatio(Theme.momentAspect, contentMode: .fit)
            .overlay(alignment: .bottom) { content }
            .overlay(alignment: .topTrailing) { infoButton }
            .clipShape(Theme.shape(Theme.Radius.hero))
            .contentShape(Theme.shape(Theme.Radius.hero))
            .onTapGesture(perform: onDetails)
            .contextMenu {
                Button("Moment Details", systemImage: "info.circle", action: onDetails)
                Button("Skip", systemImage: "forward", action: onSkip)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "Share", onShare)
            .accessibilityAction(named: "Skip", onSkip)
            .accessibilityAction(named: "Details", onDetails)
    }

    /// Black scrim under the text: at least the bottom 45% of the photo, and always 72 pt above the caption.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(scrimOpacity * 0.6), location: 0.35),
                .init(color: .black.opacity(scrimOpacity), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .padding(.top, -72)
        .allowsHitTesting(false)
    }

    private var scrimOpacity: Double { contrast == .increased ? 0.7 : 0.55 }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let caption = suggestion.caption {
                    Text(caption)
                        .font(.title2.bold())
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .foregroundStyle(reduceTransparency ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                }
                Text(model.contextLine(for: suggestion))
                    .font(.subheadline)
                    .foregroundStyle(reduceTransparency ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white.opacity(0.85)))
            }
            ReasonChips(reasons: MomentReason.chips(suggestion.displayReasons))
            ShareSkipButtons(onShare: onShare, onSkip: onSkip)
                .disabled(model.shareState == .working)
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if reduceTransparency {
                Rectangle().fill(.regularMaterial)
            } else {
                scrim
            }
        }
    }

    private var infoButton: some View {
        Button("Moment Details", systemImage: "info", action: onDetails)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(14)
    }

    private var accessibilityText: String {
        var parts = [String(localized: "Suggested moment.")]
        if let caption = suggestion.caption { parts.append(caption + ".") }
        parts.append(model.contextLine(for: suggestion) + ".")
        parts.append(suggestion.displayReasons.map(\.title).joined(separator: ", ") + ".")
        return parts.joined(separator: " ")
    }
}

enum MorphID: Hashable {
    case photo
}

/// Skip and Share with equal widths. At accessibility sizes they stack, Share on top.
struct ShareSkipButtons: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var onShare: () -> Void
    var onSkip: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    share
                    skip
                }
            } else {
                HStack(spacing: 12) {
                    skip
                    share
                }
            }
        }
        .controlSize(.large)
    }

    private var skip: some View {
        Button(action: onSkip) {
            Text("Skip").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    private var share: some View {
        Button(action: onShare) {
            Label("Share", systemImage: "faceid").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
    }
}

/// Reason chips on the photo. Clear glass over the dark scrim. Not tappable in v1.
struct ReasonChips: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let reasons: [MomentReason]

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { chips }
        } else {
            FlowLayout(spacing: 8) { chips }
        }
    }

    private var chips: some View {
        ForEach(reasons, id: \.self) { reason in
            Label(reason.title, systemImage: reason.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(reduceTransparency ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.clear, in: .capsule)
                .overlay {
                    if contrast == .increased {
                        Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1)
                    }
                }
        }
    }
}

/// Wraps children onto new lines, left aligned.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A suggestion photo from the library (or the debug fixtures), filling its frame.
struct MomentPhoto: View {
    @Environment(AppModel.self) private var model
    let assetID: String
    var side: CGFloat = 1200
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: assetID) {
                let loaded = await model.image(for: assetID, side: side)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}

// MARK: State cards

/// On-device analysis in progress, or its error. A calm glyph and one line, no percent.
struct AnalyzingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: AnalysisProgress?
    let failed: Bool
    var onStop: () -> Void
    var onRetry: () -> Void
    /// Onboarding shows the card without the Stop button.
    var showsButton = true
    @State private var drift = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: failed ? "exclamationmark.magnifyingglass" : "sparkle.magnifyingglass")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !failed && !reduceMotion)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(failed ? "Couldn't finish looking" : "Looking at your recent photos")
                    .font(.title3.bold())
                Text(failed ? "Photos analyzed so far are saved." : "On this iPhone. You can leave the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            if let progress, progress.phase == .analyzing, progress.total > 0, !failed {
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(ThinProgressStyle())
                    .frame(maxWidth: 180)
                    .accessibilityLabel("Analysis progress")
            }
            Spacer(minLength: 0)
            if showsButton {
                if failed {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                } else {
                    Button("Stop", action: onStop)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity)
        .aspectRatio(Theme.momentAspect, contentMode: .fit)
        .background { glow }
        .cardBackground(radius: Theme.Radius.hero)
        .clipShape(Theme.shape(Theme.Radius.hero))
    }

    /// A soft accent glow that drifts slowly. Static with Reduce Motion.
    private var glow: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: size.width * 0.9)
                    .offset(x: drift ? -size.width * 0.18 : size.width * 0.12, y: drift ? -size.height * 0.12 : size.height * 0.05)
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: size.width * 0.7)
                    .offset(x: drift ? size.width * 0.2 : -size.width * 0.1, y: drift ? size.height * 0.18 : -size.height * 0.05)
            }
            .frame(width: size.width, height: size.height)
            .blur(radius: 50)
        }
        .onAppear {
            guard !reduceMotion, !failed else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }
}

/// A 4 pt capsule progress bar.
struct ThinProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.secondary)
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 4)
        .animation(.smooth, value: configuration.fractionCompleted)
    }
}

/// No moment yet today. Calm, compact, one small action.
struct QuietDayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "leaf")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing stood out yet")
                    .font(.headline)
                Text("Go live a little. We'll tell you when a moment stands out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Look Now") { model.findMomentsNow() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .cardBackground()
    }
}

/// Today's moment after Share or Skip.
struct DecidedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let suggestion: Suggestion
    var namespace: Namespace.ID
    var onDetails: () -> Void
    @State private var showCheck = false

    var body: some View {
        if suggestion.decision == .skip {
            Label {
                Text("You skipped today's moment. Next one tomorrow.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "moon.zzz")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        } else {
            Button(action: onDetails) {
                HStack(spacing: 14) {
                    MomentPhoto(assetID: suggestion.assetID, side: 300)
                        .matchedGeometryEffect(id: MorphID.photo, in: namespace)
                        .frame(width: 64, height: 64)
                        .clipShape(Theme.shape(Theme.Radius.small))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            ZStack {
                                if showCheck || reduceMotion {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .transition(.symbolEffect(.drawOn))
                                }
                            }
                            .frame(width: 20)
                            Text(model.sharedAudienceText)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        Text("Disappears \(model.expiryDate(for: suggestion).formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .cardBackground()
                .contentShape(Theme.shape(Theme.Radius.card))
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.2)) { showCheck = true }
            }
        }
    }
}

/// Limited or denied photo access: Firsthand cannot find new moments.
struct LimitedAccessCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppInfo.name) can't find new moments")
                        .font(.headline)
                    Text("It can only see the photos you selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                SystemSettings.open()
            } label: {
                Text("Allow Full Access").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .controlSize(.large)
        }
        .padding(Theme.Spacing.cardPadding)
        .cardBackground()
    }
}

// MARK: Copy helpers

extension AppModel {
    /// Friends who receive my moments: my share's accepted participants.
    var audience: [Friendship] {
        friendships.filter { $0.outgoing == .accepted }
    }

    var sharedAudienceText: String {
        let count = audience.count
        return count == 1
            ? String(localized: "Shared with 1 friend")
            : String(localized: "Shared with \(count) friends")
    }

    /// The day the shared copy of this suggestion disappears.
    func expiryDate(for suggestion: Suggestion) -> Date {
        let calendar = Calendar.current
        let own = feed.filter { $0.authorID == CloudKitSharing.ownOwnerID && calendar.isDate($0.createdAt, inSameDayAs: suggestion.createdAt) }
        return own.first?.expiresAt ?? suggestion.createdAt.addingTimeInterval(PostExpiry.lifetime)
    }

    /// "Today at 6:40 PM · Near Lake Merritt".
    func contextLine(for suggestion: Suggestion) -> String {
        let date = suggestion.captureDate ?? suggestion.createdAt
        var parts = [Self.momentTime(date)]
        if let bucket = suggestion.locationBucket, let place = placeNames[bucket] {
            parts.append(String(localized: "Near \(place)"))
        }
        return parts.joined(separator: " · ")
    }

    /// "Today at 6:40 PM", "Yesterday at 9:15 AM", "Thursday at 8:02 PM".
    static func momentTime(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return String(localized: "Today at \(time)") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday at \(time)") }
        return String(localized: "\(date.formatted(.dateTime.weekday(.wide))) at \(time)")
    }
}
#endif
