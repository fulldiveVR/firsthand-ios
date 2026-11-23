#if os(iOS)
import FirsthandCore
import SwiftUI

/// Confirms a share. Names the audience and the 30-day lifetime before Face ID.
/// The caption is shown, not edited: the AI suggests, the user approves.
struct ShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let suggestion: Suggestion
    /// Called when the audience is empty and the user wants to invite someone.
    var onInvite: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 18) {
                        audienceRow
                        ShareInfoRow(symbol: "hourglass") {
                            Text("Visible until \(visibleUntil.formatted(.dateTime.month(.wide).day()))")
                        } detail: {
                            Text("Then it's deleted from iCloud.")
                        }
                        ShareInfoRow(symbol: "lock.fill") {
                            Text("Only the photo and caption are shared. No location.")
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.top, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) { footer }
            .navigationTitle("Share Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .disabled(model.shareState == .working)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(model.shareState == .working)
        .onAppear {
            if case .failed = model.shareState { model.shareState = .idle }
        }
    }

    private var visibleUntil: Date { Date().addingTimeInterval(PostExpiry.lifetime) }

    private var header: some View {
        HStack(spacing: 14) {
            MomentPhoto(assetID: suggestion.assetID, side: 300)
                .frame(width: 72, height: 72)
                .clipShape(Theme.shape(Theme.Radius.medium))
            VStack(alignment: .leading, spacing: 3) {
                if let caption = suggestion.caption {
                    Text(caption).font(.headline)
                }
                Text(model.shortContextLine(for: suggestion))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var audienceRow: some View {
        let audience = model.audience
        return ShareInfoRow(symbol: "person.2.fill") {
            if audience.isEmpty {
                Text("No friends yet")
            } else if audience.count == 1 {
                Text("Your friend \(audience[0].displayName)")
            } else {
                Text("Your \(audience.count) friends")
            }
        } detail: {
            if audience.isEmpty {
                Text("Invite someone to share with.")
            }
        } accessory: {
            AvatarStack(people: audience.map { .init(id: $0.id, name: $0.displayName) }, size: 26)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if case .failed(let message) = model.shareState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if model.audience.isEmpty {
                Button {
                    onInvite()
                } label: {
                    Label("Invite a Friend First", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    Task {
                        if await model.share() { dismiss() }
                    }
                } label: {
                    ZStack {
                        Label("Share with Face ID", systemImage: "faceid")
                            .opacity(model.shareState == .working ? 0 : 1)
                        if model.shareState == .working {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.shareState == .working)
            }
        }
        .tint(.accentColor)
        .controlSize(.large)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.bottom, 8)
    }
}

/// A symbol, a primary line, an optional secondary line and an optional trailing accessory.
struct ShareInfoRow<Title: View, Detail: View, Accessory: View>: View {
    let symbol: String
    @ViewBuilder var title: Title
    @ViewBuilder var detail: Detail
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.body)
                detail.font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

extension ShareInfoRow where Accessory == EmptyView {
    init(symbol: String, @ViewBuilder title: () -> Title, @ViewBuilder detail: () -> Detail) {
        self.init(symbol: symbol, title: title, detail: detail, accessory: { EmptyView() })
    }
}

extension ShareInfoRow where Accessory == EmptyView, Detail == EmptyView {
    init(symbol: String, @ViewBuilder title: () -> Title) {
        self.init(symbol: symbol, title: title, detail: { EmptyView() }, accessory: { EmptyView() })
    }
}

extension AppModel {
    /// "Today · Near Lake Merritt".
    func shortContextLine(for suggestion: Suggestion) -> String {
        let date = suggestion.captureDate ?? suggestion.createdAt
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = String(localized: "Today")
        } else if calendar.isDateInYesterday(date) {
            day = String(localized: "Yesterday")
        } else {
            day = date.formatted(.dateTime.weekday(.wide))
        }
        var parts = [day]
        if let bucket = suggestion.locationBucket, let place = placeNames[bucket] {
            parts.append(String(localized: "Near \(place)"))
        }
        return parts.joined(separator: " · ")
    }
}
#endif
