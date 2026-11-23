#if os(iOS)
import FirsthandCore
import SwiftUI

/// Profile & Privacy. Privacy is shown as live numbers, not as policy text.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section {
                    PrivacyStatRow(symbol: "iphone", title: "On-device analysis") {
                        Text("On")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(.green, in: Capsule())
                    }
                    PrivacyStatRow(symbol: "photo.on.rectangle", title: "Photos analyzed", subtitle: analyzedSubtitle) {
                        Text(model.analyzedPhotoCount.formatted())
                    }
                    PrivacyStatRow(symbol: "square.and.arrow.up", title: "Moments shared") {
                        Text(myPosts.count.formatted())
                    }
                    PrivacyStatRow(symbol: "icloud", title: "Stored in your iCloud", subtitle: photosText) {
                        Text(storageText)
                    }
                    if let oldest = myPosts.map(\.expiresAt).min() {
                        PrivacyStatRow(symbol: "hourglass", title: "Oldest disappears") {
                            Text(oldest.formatted(.dateTime.month(.abbreviated).day()))
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Photos never leave this iPhone unless you share them. No ads, no tracking, no \(AppInfo.name) photo server. Place names come from Apple Maps, which gets only a rough area.")
                }

                Section("Moments") {
                    Button {
                        model.findMomentsNow()
                        dismiss()
                    } label: {
                        Label("Look for a Moment Now", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(model.isManualScanRunning || model.pending != nil)
                    Button(action: SystemSettings.open) {
                        SettingsRowLabel(title: "Photo Access", systemImage: "photo", value: photoAccessText)
                    }
                    Button(action: SystemSettings.open) {
                        SettingsRowLabel(title: "Notifications", systemImage: "bell", value: model.notificationAccess == .allowed ? String(localized: "On") : String(localized: "Off"))
                    }
                    #if DEBUG
                    NavigationLink {
                        ScoringLogView()
                    } label: {
                        Label("Scoring Log", systemImage: "list.number")
                    }
                    #endif
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                }

                Section {
                    Button("Delete All Data", role: .destructive) { confirmDelete = true }
                        .id("delete")
                } footer: {
                    Text("Removes suggestions, analysis, everything you shared and your friend connections. Your photo library is not changed.")
                }
            }
            .listStyle(.insetGrouped)
            #if DEBUG
            .onAppear {
                if UserDefaults.standard.string(forKey: "demoScroll") == "bottom" { proxy.scrollTo("delete") }
            }
            #endif
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete All Data", role: .destructive) { confirmDeleteFinal = true }
            } message: {
                Text("Your friends will lose your moments, and you will lose theirs.")
            }
            .alert("This can't be undone.", isPresented: $confirmDeleteFinal) {
                Button("Delete", role: .destructive) { Task { await model.deleteAllData() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(AppInfo.name) deletes everything and signs you out.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Avatar(id: model.appleUserID ?? "me", name: model.userName ?? "", size: 72)
            Text(model.userName ?? String(localized: "You"))
                .font(.title2.bold())
            Text("Signed in with Apple")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var myPosts: [Post] { model.myPosts() }

    private var analyzedSubtitle: String {
        let days = Int(AppServices.lookback / 86_400)
        return String(localized: "Last \(days) days, on this iPhone")
    }

    private var photosText: String {
        myPosts.count == 1 ? String(localized: "1 photo") : String(localized: "\(myPosts.count) photos")
    }

    /// Local copies of my shared photos have the same size as the iCloud records.
    private var storageText: String {
        let bytes = myPosts.compactMap(\.imageURL).reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var photoAccessText: String {
        switch model.photoAccess {
        case .authorized: String(localized: "Full")
        case .limited: String(localized: "Limited")
        case .denied, .notDetermined: String(localized: "Off")
        }
    }
}

/// One privacy fact: symbol, title, optional subtitle and a trailing value.
private struct PrivacyStatRow<Value: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            value
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A settings row that opens the system Settings app.
private struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(Color.primary)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(.tint)
            }
            Spacer()
            Text(value).foregroundStyle(Color.secondary)
            Image(systemName: "arrow.up.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
#endif
