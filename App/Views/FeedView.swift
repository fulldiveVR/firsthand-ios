#if os(iOS)
import CandidCore
import SwiftUI

/// Friends' posts, newest first. No like counts, no ranking.
struct FeedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.feed.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "rectangle.stack",
                        description: Text("Moments your friends share appear here.")
                    )
                } else {
                    List(model.feed) { post in
                        PostRow(post: post)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Feed")
            .refreshable { await model.refresh() }
        }
    }
}

private struct PostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(post.authorName).font(.headline)
                Spacer()
                Text(post.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            if let url = post.imageURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if let caption = post.caption {
                Text(caption)
            }
            ProvenanceLabel(status: post.provenance)
        }
        .padding(.vertical, 8)
    }
}
#endif
