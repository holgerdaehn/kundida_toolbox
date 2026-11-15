import SwiftUI

@main
struct KundidaToolboxApp: App {
    @State private var store = ToolboxStore()
    @StateObject private var updater = AppUpdater()

    init() {
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            ToolboxView().environment(store).environmentObject(updater)
        } label: {
            let updates = store.updates.count + (updater.availableVersion == nil ? 0 : 1)
            Image(systemName: updates > 0 ? "square.grid.2x2.fill" : "square.grid.2x2")
            if updates > 0 { Text("\(updates)") }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store).environmentObject(updater)
        }
    }
}
