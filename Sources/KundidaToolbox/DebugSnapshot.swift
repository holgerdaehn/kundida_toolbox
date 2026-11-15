#if DEBUG
import AppKit
import SwiftUI

/// Nur Debug-Builds: `KT_SNAPSHOT=/pfad.png swift run` rendert das Menüleisten-Fenster als Bild.
enum DebugSnapshot {
    @MainActor static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["KT_SNAPSHOT"] else { return }
        Task { @MainActor in
            let store = ToolboxStore()
            try? await Task.sleep(for: .seconds(1))
            while store.isRefreshing { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(3)) // Symbole laden
            let rows = VStack(alignment: .leading, spacing: 0) {
                ForEach(store.tools) { t in
                    ToolRow(tool: t, expanded: ProcessInfo.processInfo.environment["KT_EXPAND"] == t.id, confirm: nil,
                            onToggle: {}, onUpdate: {}, onUninstall: {}, onConfirm: {}, onCancelConfirm: {})
                }
            }
            let renderer = ImageRenderer(content: rows.frame(width: 380).environment(store)
                .background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}
#endif
