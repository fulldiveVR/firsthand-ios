#if os(iOS)
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Label("Photos are analyzed on this iPhone only.", systemImage: "iphone")
                    Label("Nothing is shared without Face ID and your yes.", systemImage: "faceid")
                    Label("Shared photos are stored in your iCloud and visible to your friends only.", systemImage: "icloud")
                    Label("Shared moments disappear after 30 days, from your friends' feeds and from your iCloud.", systemImage: "calendar.badge.clock")
                    Label("No ads, no tracking, no own photo server.", systemImage: "hand.raised")
                }
                Section {
                    FindMomentsPanel(prominent: false)
                        .padding(.vertical, 4)
                } header: {
                    Text("Moments")
                } footer: {
                    Text("Looks at your recent photos on this iPhone now, instead of waiting for the next charge. The AI picks at most one moment.")
                }
                Section {
                    Button("Delete All Data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes your suggestions, analysis progress, everything you shared and your friend connections. Your photo library is not changed.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.deleteAllData() } }
            }
        }
    }
}
#endif
