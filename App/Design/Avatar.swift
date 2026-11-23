#if os(iOS)
import FirsthandCore
import SwiftUI

/// Monogram avatar. The color comes from a stable hash of the friend id. No photos in v1.
struct Avatar: View {
    let id: String
    let name: String
    var size: CGFloat = 40

    static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo]

    var body: some View {
        let color = Self.palette[Monogram.colorIndex(for: id) % Self.palette.count]
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(Monogram.initials(name))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    // The monogram scales with the circle, not with Dynamic Type.
                    .dynamicTypeSize(.large)
                    .scaleEffect(size / 40)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Up to `limit` overlapping avatars and a "+N" bubble.
struct AvatarStack: View {
    struct Person: Identifiable {
        var id: String
        var name: String
    }

    let people: [Person]
    var size: CGFloat = 28
    var limit = 5

    var body: some View {
        let shown = Array(people.prefix(limit))
        let extra = people.count - shown.count
        HStack(spacing: -size * 0.3) {
            ForEach(shown) { person in
                Avatar(id: person.id, name: person.name, size: size)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
            if extra > 0 {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: size, height: size)
                    .overlay {
                        Text("+\(extra)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .dynamicTypeSize(.large)
                    }
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
