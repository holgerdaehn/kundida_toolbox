import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Allgemein", systemImage: "gearshape") }
            InstallSettings().tabItem { Label("Installation", systemImage: "arrow.down.app") }
            AboutView().tabItem { Label("Über", systemImage: "info.circle") }
        }
        .frame(width: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct GeneralSettings: View {
    @AppStorage(Defaults.checkOnLaunch) private var checkOnLaunch = true
    @AppStorage(Defaults.autoCheckHours) private var autoCheckHours = 6
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }

            Toggle("Beim Start nach Updates suchen", isOn: $checkOnLaunch)
            Picker("Regelmäßig nach Updates suchen", selection: $autoCheckHours) {
                Text("Nie").tag(0)
                Text("Stündlich").tag(1)
                Text("Alle 6 Stunden").tag(6)
                Text("Täglich").tag(24)
            }
            Text("Updates werden nur angezeigt. Installiert wird ausschließlich auf deinen Klick.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct InstallSettings: View {
    @Environment(ToolboxStore.self) private var store
    @AppStorage(Defaults.installLocation) private var location = "system"
    @AppStorage(Defaults.source) private var source = defaultSource
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                Picker("Neue Apps installieren in", selection: $location) {
                    Text("Programme (/Applications)").tag("system")
                    Text("Benutzer-Programme (~/Applications)").tag("user")
                }
                .onChange(of: location) { store.rescan() }
                Text("Bereits installierte Apps werden an ihrem bisherigen Ort aktualisiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Download-Quelle") {
                TextField("Adresse oder Ordner", text: $draft)
                    .onSubmit(apply)
                HStack {
                    Button("Übernehmen", action: apply).disabled(draft == source)
                    Button("Ordner wählen …", action: chooseFolder)
                    Spacer()
                    Button("Standard") { draft = defaultSource; apply() }.disabled(source == defaultSource)
                }
                Text("Erwartet wird data/releases.json. Ein lokaler Ordner wie /Users/…/Sites/Download funktioniert ebenfalls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sicherheit") {
                Text("Jeder Download wird per SHA-256 mit dem Katalog abgeglichen und muss mit der Developer ID \(trustedTeamID) signiert sein. Sonst wird nichts installiert.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = source }
    }

    private func apply() {
        source = draft.trimmingCharacters(in: .whitespaces)
        Task { await store.refresh() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            draft = url.path
            apply()
        }
    }
}

private struct AboutView: View {
    @EnvironmentObject private var updater: AppUpdater
    @State private var autoUpdate = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Kundida Toolbox").font(.title2.weight(.semibold))
            Text(version).foregroundStyle(.secondary)
            Text("Installiert, aktualisiert und startet die Kundida-Apps.\nKeine Anmeldung, keine Telemetrie.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Toggle("Automatisch nach Toolbox-Updates suchen", isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, on in updater.automaticallyChecks = on }
            Button("Jetzt nach Updates suchen …") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        .onAppear { autoUpdate = updater.automaticallyChecks }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
