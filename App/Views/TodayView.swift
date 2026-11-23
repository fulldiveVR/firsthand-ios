#if os(iOS)
import FirsthandCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.photoAccess.isDegraded {
                        LimitedAccessBanner()
                    }
                    if let suggestion = model.pending {
                        SuggestionCard(suggestion: suggestion)
                    } else {
                        EmptyTodayCard()
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
        }
    }
}

/// No moment today. The user can ask the AI to look now, invite friends or see friends' moments.
/// There is no photo picker: the AI picks, the user only says Share or Skip.
private struct EmptyTodayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text("Go live a little. We'll find the moment.")
                    .font(.title2.bold())
                Text("Take a walk, meet a friend, try somewhere new. When a moment stands out, you get a notification.")
                    .foregroundStyle(.secondary)
            }

            FindMomentsPanel()

            Divider()

            if model.hasFriends {
                Button {
                    model.selectedTab = .feed
                } label: {
                    Label("See friends' moments", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Moments are better with friends. Only people you invite can see what you share.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.makeInvite() }
                    } label: {
                        Label("Invite friends", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The only actions are Share and Skip. The user cannot pick a different photo.
private struct SuggestionCard: View {
    @Environment(AppModel.self) private var model
    let suggestion: Suggestion
    @State private var image: UIImage?
    @State private var confirmShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color(.secondarySystemBackground)
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))

            ProvenanceLabel(status: suggestion.provenance)

            if let caption = suggestion.caption {
                Text(caption).font(.body)
            }

            if case .failed(let message) = model.shareState {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Skip") { Task { await model.skip() } }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button {
                    confirmShare = true
                } label: {
                    Label("Share", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.shareState == .working)
        }
        .confirmationDialog("Share with your friends?", isPresented: $confirmShare, titleVisibility: .visible) {
            Button("Share with Face ID") { Task { await model.share() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your friends can see this for 30 days. Then it disappears from their feed and your iCloud.")
        }
        .task(id: suggestion.assetID) {
            image = await model.image(for: suggestion.assetID, side: 1200)
        }
    }
}

/// Describes what is known about the photo source. Never says "verified".
struct ProvenanceLabel: View {
    let status: ProvenanceStatus

    var body: some View {
        switch status {
        case .hasReferenceImageData:
            Label("Contains camera reference data", systemImage: "checkmark.seal")
                .font(.caption).foregroundStyle(.secondary)
        case .likelyCamera:
            Label("Likely taken with a camera", systemImage: "camera")
                .font(.caption).foregroundStyle(.secondary)
        case .unknown:
            Label("Source unknown", systemImage: "questionmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .excluded:
            EmptyView()
        }
    }
}

private struct LimitedAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Limited photo access")
                .font(.subheadline.bold())
            Text("\(AppInfo.name) can see only the photos you selected, so it cannot find new moments. Allow full access in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open Settings") { SystemSettings.open() }
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
