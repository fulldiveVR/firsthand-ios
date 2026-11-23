#if os(iOS)
import FirsthandCore
import MapKit
import SwiftUI

/// What Moment details shows: today's suggestion (mine) or a shared post (mine or a friend's).
enum MomentRoute: Hashable, Identifiable {
    case suggestion(Suggestion)
    case post(Post)

    var id: String {
        switch self {
        case .suggestion(let s): "suggestion-\(s.id.uuidString)"
        case .post(let p): "post-\(p.authorID)-\(p.id.uuidString)"
        }
    }
}

/// The zoom transition namespace of the home screen.
extension EnvironmentValues {
    @Entry var momentsNamespace: Namespace.ID?
}

extension View {
    /// Marks a card as the source of the zoom transition into Moment details.
    @ViewBuilder
    func momentTransitionSource(_ id: String) -> some View {
        modifier(MomentTransitionSource(id: id))
    }
}

private struct MomentTransitionSource: ViewModifier {
    @Environment(\.momentsNamespace) private var namespace
    let id: String

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Zoom from the card. With Reduce Motion, a cross-fade on iOS 27 and the default push on iOS 26.
struct MomentDetailsTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if reduceMotion {
            if #available(iOS 27, *) {
                content.navigationTransition(.crossFade)
            } else {
                content.navigationTransition(.automatic)
            }
        } else {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        }
    }
}

/// Why, where, origin and visibility of one moment. Place is coarse: never coordinates or a map pin.
struct MomentDetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let route: MomentRoute
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailPhoto(route: route)
                    .backgroundExtensionEffect()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let caption {
                            Text(caption).font(.title2.bold())
                        }
                        Text(bylineText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                    if case .suggestion(let suggestion) = route {
                        DetailGroup(title: "Why this moment") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(suggestion.displayReasons.filter { !$0.isProvenance }, id: \.self) { reason in
                                    Label(reason.title, systemImage: reason.symbolName)
                                }
                                if suggestion.displayReasons.allSatisfy(\.isProvenance) {
                                    Text("It stood out among your recent photos.")
                                }
                            }
                        }
                        if let place {
                            DetailGroup(title: "Place") {
                                Label(String(localized: "Near \(place)"), systemImage: "mappin.and.ellipse")
                            }
                        }
                    }
                    DetailGroup(title: "Origin") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(provenance.originTitle, systemImage: provenance.originSymbol)
                            Text(originNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let visibility {
                        DetailGroup(title: "Visibility") {
                            Label(visibility, systemImage: "hourglass")
                        }
                    }
                }
                .padding(Theme.Spacing.cardPadding)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let ownPost {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Delete Moment", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("Delete this moment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete Moment", role: .destructive) {
                            Task {
                                await model.delete(ownPost)
                                dismiss()
                            }
                        }
                    } message: {
                        Text("Your friends will no longer see it.")
                    }
                }
            }
        }
        .task(id: route.id) {
            if case .suggestion(let suggestion) = route { await model.resolvePlace(for: suggestion) }
        }
    }

    private var caption: String? {
        switch route {
        case .suggestion(let s): s.caption
        case .post(let p): p.caption
        }
    }

    private var provenance: ProvenanceStatus {
        switch route {
        case .suggestion(let s): s.provenance
        case .post(let p): p.provenance
        }
    }

    private var bylineText: String {
        switch route {
        case .suggestion(let s):
            return Self.longDate(s.captureDate ?? s.createdAt)
        case .post(let p):
            let name = p.authorID == CloudKitSharing.ownOwnerID ? String(localized: "You") : p.authorName
            return "\(name) · \(Self.longDate(p.createdAt))"
        }
    }

    static func longDate(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let time = date.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(day) at \(time)")
    }

    private var place: String? {
        guard case .suggestion(let s) = route, let bucket = s.locationBucket else { return nil }
        return model.placeNames[bucket]
    }

    private var originNote: String {
        switch provenance {
        case .hasReferenceImageData, .likelyCamera:
            String(localized: "The photo has camera data and is not a screenshot or an edited copy. \(AppInfo.name) can't prove where a photo came from.")
        case .unknown, .excluded:
            String(localized: "\(AppInfo.name) found no camera data for this photo.")
        }
    }

    private var ownPost: Post? {
        if case .post(let p) = route, p.authorID == CloudKitSharing.ownOwnerID { return p }
        return nil
    }

    private var visibility: String? {
        let friends = model.audience.count
        switch route {
        case .suggestion(let s):
            switch s.decision {
            case .share:
                let until = model.expiryDate(for: s).formatted(.dateTime.month(.wide).day())
                return String(localized: "Visible to your \(friends) friends until \(until)")
            case .skip:
                return String(localized: "Skipped. Only you saw it.")
            case nil:
                return String(localized: "Not shared. Only you can see it.")
            }
        case .post(let p):
            if p.authorID == CloudKitSharing.ownOwnerID {
                let until = p.expiresAt.formatted(.dateTime.month(.wide).day())
                return String(localized: "Visible to your \(friends) friends until \(until)")
            }
            let days = p.daysLeft(now: Date())
            return days <= 1
                ? String(localized: "Disappears within a day")
                : String(localized: "Disappears in \(days) days")
        }
    }
}

/// A titled group with a filled background.
private struct DetailGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .backgroundStyle(Color(.secondarySystemBackground))
    }
}

/// The full photo at its native aspect.
private struct DetailPhoto: View {
    @Environment(AppModel.self) private var model
    let route: MomentRoute
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .aspectRatio(Theme.momentAspect, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .task(id: route.id) {
            switch route {
            case .suggestion(let s): image = await model.image(for: s.assetID, side: 2000)
            case .post(let p): image = await PostImageCache.shared.image(at: p.imageURL)
            }
        }
    }
}

// MARK: Place names

extension AppModel {
    /// Reverse-geocodes the coarse bucket center to a city name, once per bucket.
    /// Apple Maps receives only the center of an area about 1 km wide.
    func resolvePlace(for suggestion: Suggestion) async {
        guard let bucket = suggestion.locationBucket, placeNames[bucket] == nil,
              let center = PhotoKitLibrary.bucketCenter(bucket),
              let request = MKReverseGeocodingRequest(location: CLLocation(latitude: center.latitude, longitude: center.longitude))
        else { return }
        guard let item = try? await request.mapItems.first,
              let name = item.addressRepresentations?.cityName ?? item.name
        else { return }
        placeNames[bucket] = name
    }
}
#endif
