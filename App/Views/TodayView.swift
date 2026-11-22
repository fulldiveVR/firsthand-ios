#if os(iOS)
import FirsthandCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if model.photoAccess.isDegraded {
                    LimitedAccessBanner()
                }
                if let suggestion = model.pending {
                    SuggestionCard(suggestion: suggestion)
                } else {
                    ContentUnavailableView(
                        "Go live a little. We'll find a moment.",
                        systemImage: "sparkles",
                        description: Text("You get a notification when a moment is ready.")
                    )
                }
            }
            .padding()
            .navigationTitle("Today")
        }
    }
}

/// The only actions are Share and Skip. The user cannot pick a different photo.
private struct SuggestionCard: View {
    @Environment(AppModel.self) private var model
    let suggestion: Suggestion
    @State private var image: UIImage?

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
                    Task { await model.share() }
                } label: {
                    Label("Share", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.shareState == .working)
        }
        .task(id: suggestion.assetID) {
            image = await model.services.library.thumbnail(for: suggestion.assetID, side: 1200)
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
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
