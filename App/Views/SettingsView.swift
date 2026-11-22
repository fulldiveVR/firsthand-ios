#if os(iOS)
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Label("Photos are analyzed on this iPhone only.", systemImage: "iphone")
                    Label("Nothing is shared without Face ID and your yes.", systemImage: "faceid")
                    Label("Shared photos are stored in your iCloud and visible to your friends only.", systemImage: "icloud")
                    Label("No ads, no tracking, no own photo server.", systemImage: "hand.raised")
                }
                Section {
                    Button("Delete All Data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes your suggestions, analysis progress and everything you shared. Your photo library is not changed.")
                }
                #if DEBUG
                Section("Debug") {
                    Button("Analyze Now") { Task { await model.analyzeNow() } }
                }
                #endif
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.deleteAllData() } }
            }
        }
    }
}
#endif
