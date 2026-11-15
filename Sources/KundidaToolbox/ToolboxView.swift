import AppKit
import SwiftUI

/// Hauptfenster der Menüleisten-App: installierte und verfügbare Kundida-Apps.
struct ToolboxView: View {
    @Environment(ToolboxStore.self) private var store
    @EnvironmentObject private var updater: AppUpdater
    @State private var search = ""
    @State private var expanded: String?
    @State private var confirm: Confirm?

    struct Confirm: Equatable {
        enum Kind { case update, uninstall }
        let id: String
        let kind: Kind
    }

    private var filtered: [CatalogTool] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.tools }
        return store.tools.filter {
            $0.release.name.localizedCaseInsensitiveContains(q) || ($0.release.tagline ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let version = updater.availableVersion { selfUpdateBanner(version) }
            searchField
            Divider()
            content
            if let notice = store.notice { noticeBar(notice) }
            Divider()
            footer
        }
        .frame(width: 380, height: 680)
        .onAppear { store.rescan() }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("Kundida Toolbox").font(.headline)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Nach Updates suchen")
            .keyboardShortcut("r")
            .disabled(store.isRefreshing)

            Menu {
                SettingsLink { Text("Einstellungen …") }
                    .keyboardShortcut(",")
                Button("Toolbox-Updates suchen …") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Divider()
                Button("Kundida Toolbox beenden") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func selfUpdateBanner(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kundida Toolbox \(version) ist verfügbar").font(.callout.weight(.semibold))
                Text("Neuerungen und Installation im Update-Fenster").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Aktualisieren") { updater.checkForUpdates() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Apps durchsuchen", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: Liste

    @ViewBuilder
    private var content: some View {
        if store.tools.isEmpty {
            emptyState
        } else if filtered.isEmpty {
            placeholder(icon: "magnifyingglass", title: "Keine Treffer", text: "Keine App passt zu „\(search)“.")
        } else {
            let installed = filtered.filter { store.installed[$0.id] != nil }
            let available = filtered.filter { store.installed[$0.id] == nil }
            let updates = installed.filter { store.hasUpdate($0) && !store.usesAppStore($0) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !installed.isEmpty {
                        sectionHeader("Installiert", count: installed.count) {
                            if updates.count > 1 {
                                Button("Alle aktualisieren") { updateAll(updates) }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                        ForEach(installed) { row($0) }
                    }
                    if !available.isEmpty {
                        sectionHeader("Verfügbar", count: available.count) { EmptyView() }
                        ForEach(available) { row($0) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func sectionHeader<Trailing: View>(_ title: String, count: Int, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func row(_ t: CatalogTool) -> some View {
        ToolRow(
            tool: t,
            expanded: expanded == t.id,
            confirm: confirm?.id == t.id ? confirm?.kind : nil,
            onToggle: { withAnimation(.easeOut(duration: 0.15)) { expanded = expanded == t.id ? nil : t.id } },
            onUpdate: { requestUpdate(t) },
            onUninstall: { confirm = Confirm(id: t.id, kind: .uninstall) },
            onConfirm: {
                let kind = confirm?.kind
                confirm = nil
                Task {
                    if kind == .uninstall { await store.uninstall(t) } else { await store.install(t) }
                }
            },
            onCancelConfirm: { confirm = nil }
        )
    }

    private func requestUpdate(_ t: CatalogTool) {
        if store.isRunning(t) {
            confirm = Confirm(id: t.id, kind: .update)
        } else {
            Task { await store.install(t) }
        }
    }

    private func updateAll(_ tools: [CatalogTool]) {
        let running = tools.filter { store.isRunning($0) }
        Task {
            for t in tools where !running.contains(t) { await store.install(t) }
            if !running.isEmpty {
                store.show("Läuft gerade, bitte einzeln aktualisieren: \(running.map(\.release.name).joined(separator: ", ")).")
            }
        }
    }

    // MARK: Leer- und Statuszustände

    @ViewBuilder
    private var emptyState: some View {
        if store.isRefreshing {
            VStack { Spacer(); ProgressView("Katalog wird geladen …"); Spacer() }.frame(maxWidth: .infinity)
        } else {
            placeholder(icon: "wifi.exclamationmark", title: "Katalog nicht verfügbar", text: store.loadError ?? "Es wurden noch keine Apps geladen.") {
                Button("Erneut versuchen") { Task { await store.refresh() } }
            }
        }
    }

    private func placeholder(icon: String, title: String, text: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            action().padding(.top, 4)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func noticeBar(_ n: ToolboxStore.Notice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: n.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .orange : .green)
            Text(n.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { store.notice = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var footer: some View {
        HStack {
            if store.loadError != nil, !store.tools.isEmpty {
                Label("Offline – zeige letzten Stand", systemImage: "wifi.slash")
            } else if let date = store.lastChecked {
                Text("Zuletzt geprüft: \(date.formatted(date: .omitted, time: .shortened)) Uhr")
            } else {
                Text("Noch nicht geprüft")
            }
            Spacer()
            let n = store.updates.count + (updater.availableVersion == nil ? 0 : 1)
            Text(n == 0 ? "Alles aktuell" : n == 1 ? "1 Update" : "\(n) Updates")
                .foregroundStyle(n == 0 ? Color.secondary : Color.accentColor)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Zeile

struct ToolRow: View {
    @Environment(ToolboxStore.self) private var store
    let tool: CatalogTool
    let expanded: Bool
    let confirm: ToolboxView.Confirm.Kind?
    let onToggle: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onConfirm: () -> Void
    let onCancelConfirm: () -> Void
    @State private var hovering = false

    private var app: InstalledApp? { store.installed[tool.id] }
    private var phase: ToolboxStore.Phase? { store.phases[tool.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                ToolIcon(tool: tool, installed: app)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tool.release.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let version { Text(version).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary) }
                        sourceBadge
                    }
                    if let summary = tool.summary {
                        Text(summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    status
                }
                Spacer(minLength: 6)
                actions
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onTapGesture(count: 2) { if app != nil { store.open(tool) } }

            if expanded { details }
            if let confirm { confirmBar(confirm) }
        }
        .background(hovering || expanded ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
    }

    /// Installierte Version, sonst die angebotene.
    private var version: String? {
        if let app { return app.version }
        let v = store.availableVersion(tool)
        return v == "–" ? nil : v
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if store.usesAppStore(tool) || (!tool.isDirect && tool.appStore != nil) {
            badge("App Store")
        } else if tool.github != nil {
            badge("GitHub")
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(.tertiary, lineWidth: 0.8))
    }

    /// Zusätzliche Zeile nur, wenn es etwas zu melden gibt.
    @ViewBuilder
    private var status: some View {
        Group {
            switch phase {
            case .downloading(let p): Text("Wird geladen … \(Int(p * 100)) %").foregroundStyle(Color.accentColor)
            case .verifying: Text("Wird geprüft …").foregroundStyle(Color.accentColor)
            case .installing: Text("Wird installiert …").foregroundStyle(Color.accentColor)
            case nil:
                if app != nil, store.hasUpdate(tool) {
                    Text("Update auf \(store.availableVersion(tool)) verfügbar").foregroundStyle(Color.accentColor)
                } else if app == nil, let reason = tool.unsupportedReason {
                    Text(reason).foregroundStyle(.orange)
                } else if app == nil, tool.github != nil, !tool.isDirect {
                    Text("Kein macOS-Download – Anleitung auf GitHub").foregroundStyle(.tertiary)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
    }

    @ViewBuilder
    private var actions: some View {
        if let phase {
            if case .downloading(let p) = phase {
                ProgressView(value: p).frame(width: 60)
                Button { store.cancel(tool) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Abbrechen")
            } else {
                ProgressView().controlSize(.small)
            }
        } else if app != nil {
            if store.hasUpdate(tool) {
                if store.usesAppStore(tool) {
                    Button("App Store") { store.openAppStore(tool) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Update im App Store installieren")
                } else {
                    Button("Aktualisieren", action: onUpdate)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Button("Öffnen") { store.open(tool) }
                    .controlSize(.small)
            }
            Menu {
                Button("Öffnen") { store.open(tool) }
                Button("Im Finder zeigen") { store.reveal(tool) }
                if store.hasUpdate(tool), !store.usesAppStore(tool) { Button("Auf \(tool.release.version) aktualisieren", action: onUpdate) }
                if tool.appStore != nil { Button("Im App Store zeigen") { store.openAppStore(tool) } }
                if tool.github != nil { Button("Auf GitHub zeigen") { store.openGitHub(tool) } }
                Divider()
                Button("Deinstallieren …", role: .destructive, action: onUninstall)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else if tool.unsupportedReason != nil {
            Text("Nicht verfügbar").font(.caption).foregroundStyle(.tertiary)
        } else if !tool.isDirect, tool.github != nil {
            Button("GitHub") { store.openGitHub(tool) }
                .controlSize(.small)
                .help("Projektseite auf GitHub öffnen")
        } else if !tool.isDirect {
            Button("App Store") { store.openAppStore(tool) }
                .controlSize(.small)
                .help("Im App Store laden")
        } else {
            Button("Installieren") { Task { await store.install(tool) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var details: some View {
        let r = tool.release
        let appStore = store.usesAppStore(tool)
        let notes = store.releaseNotes(tool)
        return VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                if let tagline = r.tagline { detail("Beschreibung", tagline) }
                detail("Quelle", appStore ? "App Store" : tool.github.map { "GitHub (\($0.repo))" } ?? "download.kundida.de")
                if appStore {
                    detail("Verfügbar", store.availableVersion(tool))
                } else {
                    detail("Verfügbar", [r.version, store.availableBuild(tool).map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                }
                if let app { detail("Installiert", app.build.isEmpty || app.build == app.version ? app.version : "\(app.version) (\(app.build))") }
                if !appStore, let date = r.date { detail("Veröffentlicht", date) }
                if !appStore, let size = r.size { detail("Größe", size) }
                if let minOS = r.minOS { detail("Voraussetzung", minOS) }
                if let arch = r.arch { detail("Architektur", arch) }
                if tool.github != nil {
                    if tool.isDirect { detail("Sicherheit", "SHA-256 von GitHub geprüft, ohne Developer-ID-Signatur") }
                } else if !appStore {
                    detail("Sicherheit", r.notarized == true ? "Developer ID, notarisiert, SHA-256 geprüft" : "Developer ID, SHA-256 geprüft")
                }
                if let app { detail("Ort", app.url.path) }
            }
            if notes.text != nil || notes.url != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Neuerungen").font(.caption.weight(.semibold))
                    if let text = notes.text {
                        Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = notes.url { Link("Versionshinweise öffnen", destination: url) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .font(.caption)
        .padding(.leading, 63)
        .padding(.trailing, 14)
        .padding(.bottom, 10)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }

    private func confirmBar(_ kind: ToolboxView.Confirm.Kind) -> some View {
        let name = tool.release.name
        let running = store.isRunning(tool)
        let text: String
        let button: String
        switch kind {
        case .update:
            text = "\(name) läuft gerade und wird für das Update beendet."
            button = "Beenden & aktualisieren"
        case .uninstall:
            text = running ? "\(name) wird beendet und in den Papierkorb gelegt." : "\(name) in den Papierkorb legen?"
            button = "Deinstallieren"
        }
        return HStack(spacing: 8) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Abbrechen", action: onCancelConfirm).controlSize(.small)
            Button(button, role: kind == .uninstall ? .destructive : nil, action: onConfirm)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(kind == .uninstall ? .red : .accentColor)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// App-Symbol: bei installierten Apps das echte Symbol, sonst das Bild aus dem Katalog.
struct ToolIcon: View {
    @Environment(ToolboxStore.self) private var store
    let tool: CatalogTool
    let installed: InstalledApp?

    var body: some View {
        Group {
            if let installed {
                Image(nsImage: NSWorkspace.shared.icon(forFile: installed.url.path)).resizable()
            } else {
                AsyncImage(url: store.iconURL(tool)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay(Text(String(tool.release.name.prefix(1))).font(.headline).foregroundStyle(.secondary))
                }
            }
        }
        .frame(width: 38, height: 38)
    }
}
