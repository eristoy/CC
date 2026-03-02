import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            WatchFoldersSettingsView()
                .tabItem { Label("Watch Folders", systemImage: "folder.badge.questionmark") }
                .tag(1)

            DestinationsSettingsView()
                .tabItem { Label("Destinations", systemImage: "externaldrive") }
                .tag(2)

            Text("History")                 // Replaced in Plan 04
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(3)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(4)
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}
