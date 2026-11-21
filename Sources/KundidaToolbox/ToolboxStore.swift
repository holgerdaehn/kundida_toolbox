import AppKit
import Foundation
import Observation

enum Defaults {
    static let source = "sourceURL"
    static let installLocation = "installLocation" // "system" | "user"
    static let checkOnLaunch = "checkOnLaunch"
    static let autoCheckHours = "autoCheckHours" // 0 = aus
}

@MainActor @Observable
final class ToolboxStore {
    enum Phase: Equatable {
        case downloading(Double)
        case verifying
        case installing
    }

    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private(set) var tools: [CatalogTool] = []
    private(set) var installed: [String: InstalledApp] = [:]
    private(set) var appcasts: [String: AppcastInfo] = [:]
    private(set) var appStoreApps: [AppStoreApp] = []
    private(set) var githubTools: [CatalogTool] = []
    @ObservationIgnored private var directTools: [CatalogTool] = []
    private(set) var phases: [String: Phase] = [:]
    private(set) var isRefreshing = false
    private(set) var lastChecked: Date?
    private(set) var loadError: String?
    var notice: Notice?

    @ObservationIgnored private var downloads: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var observations: [String: NSKeyValueObservation] = [:]

    init() {
        UserDefaults.standard.register(defaults: [
            Defaults.source: defaultSource,
            Defaults.installLocation: "system",
            Defaults.checkOnLaunch: true,
            Defaults.autoCheckHours: 6,
        ])
        loadCachedCatalog()
        rescan()
        Task { await startScheduler() }
        watchInstalledApps()
    }

    /// Installierte Versionen aktuell halten: Apps aktualisieren sich auch selbst (Sparkle)
    /// oder über den App Store. Ohne erneutes Einlesen zeigte die Menüleiste veraltete Updates.
    private func watchInstalledApps() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            }
        }
        // Updates ohne Start/Beenden (z. B. App Store im Hintergrund): günstige Prüfung je Minute.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.rescan()
            }
        }
    }

    // MARK: - Abgeleitete Werte

    var updates: [CatalogTool] { tools.filter(hasUpdate) }

    /// Eigener Eintrag der Toolbox in releases.json – sie aktualisiert sich selbst über Sparkle.
    static let selfID = "kundidatoolbox"

    private func apply(_ all: [CatalogTool]) {
        directTools = all.filter { $0.id != Self.selfID }
        merge()
    }

    /// Direktdownloads und App-Store-Apps zu einer Liste zusammenführen (gleicher Name = gleiche App).
    private func merge() {
        var result = directTools + githubTools.filter { g in !directTools.contains { $0.id == g.id } }
        for app in appStoreApps {
            let key = normalizedName(app.name)
            if let i = result.firstIndex(where: { $0.id == key || normalizedName($0.release.name) == key }) {
                result[i].appStore = app
            } else {
                result.append(app.asTool)
            }
        }
        tools = result.sorted { $0.release.name.localizedStandardCompare($1.release.name) == .orderedAscending }
    }

    /// Alle App-Store-Apps des Entwicklerkontos (Mac und iPhone/iPad).
    private static func loadAppStore() async -> [AppStoreApp]? {
        var apps: [AppStoreApp] = []
        for entity in ["macSoftware", "software"] {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appStoreDeveloperID)&entity=\(entity)&country=de"),
                  let data = try? await fetch(url),
                  let lookup = try? JSONDecoder().decode(AppStoreLookup.self, from: data) else { return nil }
            apps += lookup.apps.filter { a in !apps.contains { $0.trackId == a.trackId } }
        }
        return apps
    }

    /// Kostenlose Tools von GitHub: neuestes Release mit macOS-ZIP und SHA-256-Digest.
    private static func loadGitHub() async -> [CatalogTool]? {
        struct Repo: Decodable { let description: String?; let html_url: URL }
        struct Asset: Decodable { let name: String; let browser_download_url: String; let size: Int; let digest: String? }
        struct Rel: Decodable { let tag_name: String; let published_at: String?; let body: String?; let assets: [Asset] }
        var result: [CatalogTool] = []
        for src in githubSources {
            guard let url = URL(string: "https://api.github.com/repos/\(src.repo)"),
                  let data = try? await fetch(url),
                  let repo = try? JSONDecoder().decode(Repo.self, from: data) else { return nil }
            let rel = await (try? fetch(url.appendingPathComponent("releases/latest")))
                .flatMap { try? JSONDecoder().decode(Rel.self, from: $0) }
            let asset = rel?.assets.first { $0.name.lowercased().contains("mac") && $0.name.lowercased().hasSuffix(".zip") }
            // Ohne Prüfsumme wird nichts installiert.
            let sha = asset?.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil } ?? ""
            let version = rel.map { $0.tag_name.hasPrefix("v") ? String($0.tag_name.dropFirst()) : $0.tag_name } ?? "–"
            let release = Release(
                name: src.name, tagline: repo.description, version: version, build: nil,
                date: rel?.published_at.map { String($0.prefix(10)) }, file: sha.isEmpty ? "" : (asset?.browser_download_url ?? ""),
                size: asset.map { ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file) },
                sha256: sha, minOS: nil, arch: nil, notarized: false)
            result.append(CatalogTool(id: normalizedName(src.name), release: release,
                                      github: GitHubInfo(repo: src.repo, appName: src.appName, pageURL: repo.html_url, notes: rel?.body)))
        }
        return result
    }

    /// Build-Referenz: Appcast (= CFBundleVersion), sonst der Build aus releases.json.
    func availableBuild(_ t: CatalogTool) -> String? { appcasts[t.id]?.build ?? t.release.build }

    /// Wird die App über den App Store gepflegt? (installierte App-Store-Version oder reine App-Store-App)
    func usesAppStore(_ t: CatalogTool) -> Bool {
        t.appStore != nil && (installed[t.id]?.fromAppStore ?? !t.isDirect)
    }

    func availableVersion(_ t: CatalogTool) -> String {
        usesAppStore(t) ? (t.appStore?.version ?? t.release.version) : t.release.version
    }

    func hasUpdate(_ t: CatalogTool) -> Bool {
        guard let app = installed[t.id] else { return false }
        if usesAppStore(t) {
            return t.appStore.map { $0.version.compare(app.version, options: .numeric) == .orderedDescending } ?? false
        }
        // Eine App-Store-Installation ohne App-Store-Eintrag wird nicht mit dem Direktdownload verglichen.
        if app.fromAppStore || !t.isDirect { return false }
        return t.isNewer(than: app, build: availableBuild(t))
    }

    /// Versionshinweise: App Store bzw. Appcast.
    func releaseNotes(_ t: CatalogTool) -> (text: String?, url: URL?) {
        if usesAppStore(t) { return (t.appStore?.releaseNotes.flatMap(AppcastInfo.plainText), nil) }
        if let g = t.github { return (g.notes.flatMap(AppcastInfo.markdownText), g.pageURL.appendingPathComponent("releases")) }
        return (appcasts[t.id]?.notes, appcasts[t.id]?.notesURL)
    }

    func openAppStore(_ t: CatalogTool) {
        if let url = t.appStore?.storeURL { NSWorkspace.shared.open(url) }
    }

    func openGitHub(_ t: CatalogTool) {
        if let url = t.github?.pageURL { NSWorkspace.shared.open(url) }
    }

    var sourceBase: URL? {
        let s = (UserDefaults.standard.string(forKey: Defaults.source) ?? defaultSource).trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("/") { return URL(fileURLWithPath: s, isDirectory: true) }
        guard let url = URL(string: s), ["https", "http", "file"].contains(url.scheme ?? "") else { return nil }
        return url
    }

    var installDirectory: URL {
        UserDefaults.standard.string(forKey: Defaults.installLocation) == "user"
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            : URL(fileURLWithPath: "/Applications")
    }

    func iconURL(_ t: CatalogTool) -> URL? {
        if t.github != nil { return nil }
        return t.isDirect ? sourceBase?.appendingPathComponent("assets/img/\(t.id).png") : t.appStore?.artwork
    }

    func isRunning(_ t: CatalogTool) -> Bool { runningApp(t) != nil }

    // MARK: - Katalog

    private var cacheFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("de.kundida.Toolbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("releases.json")
    }

    private var appStoreCacheFile: URL { cacheFile.deletingLastPathComponent().appendingPathComponent("appstore.json") }

    private var githubCacheFile: URL { cacheFile.deletingLastPathComponent().appendingPathComponent("github.json") }

    private var appcastCacheFile: URL { cacheFile.deletingLastPathComponent().appendingPathComponent("appcasts.json") }

    private func loadCachedCatalog() {
        if let data = try? Data(contentsOf: cacheFile), let all = try? decode(data) { apply(all) }
        if let data = try? Data(contentsOf: appcastCacheFile),
           let casts = try? JSONDecoder().decode([String: AppcastInfo].self, from: data) { appcasts = casts }
        if let data = try? Data(contentsOf: appStoreCacheFile),
           let apps = try? JSONDecoder().decode([AppStoreApp].self, from: data) { appStoreApps = apps; merge() }
        if let data = try? Data(contentsOf: githubCacheFile),
           let tools = try? JSONDecoder().decode([CatalogTool].self, from: data) { githubTools = tools; merge() }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ToolboxError("Server antwortet mit HTTP \(http.statusCode).")
        }
        return data
    }

    /// Lädt die Appcasts aller Apps parallel; Apps ohne Appcast bleiben einfach ohne Eintrag.
    private func loadAppcasts(base: URL, ids: [String]) async -> [String: AppcastInfo] {
        await withTaskGroup(of: (String, AppcastInfo?).self) { group in
            for id in ids {
                group.addTask {
                    let data = try? await Self.fetch(base.appendingPathComponent("appcast/\(id).xml"))
                    return (id, data.flatMap { AppcastInfo.parse($0) })
                }
            }
            var result: [String: AppcastInfo] = [:]
            for await (id, info) in group { if let info { result[id] = info } }
            return result
        }
    }

    private func decode(_ data: Data) throws -> [CatalogTool] {
        let feed = try JSONDecoder().decode(ReleaseFeed.self, from: data)
        return feed.apps
            .compactMap { key, entry in entry.value.map { CatalogTool(id: key, release: $0) } }
            .sorted { $0.release.name.localizedStandardCompare($1.release.name) == .orderedAscending }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; rescan() }
        do {
            guard let base = sourceBase else { throw ToolboxError("Die Download-Quelle in den Einstellungen ist ungültig.") }
            let data = try await Self.fetch(base.appendingPathComponent("data/releases.json"))
            let newTools = try decode(data)
            async let casts = loadAppcasts(base: base, ids: newTools.map(\.id))
            async let store = Self.loadAppStore()
            async let github = Self.loadGitHub()
            appcasts = await casts
            if let tools = await github {
                githubTools = tools
                try? JSONEncoder().encode(tools).write(to: githubCacheFile, options: .atomic)
            }
            if let apps = await store {
                appStoreApps = apps
                try? JSONEncoder().encode(apps).write(to: appStoreCacheFile, options: .atomic)
            }
            apply(newTools)
            try? data.write(to: cacheFile, options: .atomic)
            try? JSONEncoder().encode(appcasts).write(to: appcastCacheFile, options: .atomic)
            lastChecked = Date()
            loadError = nil
        } catch {
            loadError = "Katalog konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    /// Sucht installierte Apps in /Applications, ~/Applications und dem gewählten Installationsort.
    func rescan() {
        let fm = FileManager.default
        let dirs = [installDirectory, URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [String: InstalledApp] = [:]
        for t in tools {
            for dir in dirs {
                let url = dir.appendingPathComponent("\(t.appName).app")
                if fm.fileExists(atPath: url.path), let app = InstalledApp.read(at: url) {
                    found[t.id] = app
                    break
                }
            }
        }
        if found != installed { installed = found }
    }

    private func startScheduler() async {
        if UserDefaults.standard.bool(forKey: Defaults.checkOnLaunch) { await refresh() }
        while !Task.isCancelled {
            let hours = UserDefaults.standard.integer(forKey: Defaults.autoCheckHours)
            try? await Task.sleep(for: .seconds(Double(max(hours, 1)) * 3600))
            // Nur prüfen – installiert wird ausschließlich auf Klick.
            if UserDefaults.standard.integer(forKey: Defaults.autoCheckHours) > 0 { await refresh() }
        }
    }

    // MARK: - Aktionen

    func open(_ t: CatalogTool) {
        guard let app = installed[t.id] else { return }
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in self.show("\(t.release.name) konnte nicht gestartet werden: \(error.localizedDescription)", error: true) }
            }
        }
    }

    func reveal(_ t: CatalogTool) {
        guard let app = installed[t.id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func cancel(_ t: CatalogTool) { downloads[t.id]?.cancel() }

    /// Lädt, prüft (SHA-256, Signatur) und entpackt eine App. Liefert das App-Paket im Arbeitsordner.
    private func fetchVerifiedApp(_ t: CatalogTool, work: URL) async throws -> URL {
        guard let url = t.downloadURL(base: sourceBase) else { throw ToolboxError("Ungültige Download-Quelle.") }
        phases[t.id] = .downloading(0)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("download.zip")
        try await download(url, to: zip, id: t.id)
        phases[t.id] = .verifying
        try await Installer.verifyChecksum(zip, expected: t.release.sha256)
        let unpacked = work.appendingPathComponent("entpackt")
        try await Installer.unzip(zip, to: unpacked)
        let app = try Installer.findApp(in: unpacked)
        // Kundida-Apps: Developer ID Pflicht. GitHub-Tools: gültige Signatur + SHA-256 von GitHub.
        try Installer.verifySignature(app, teamID: t.github == nil ? trustedTeamID : nil)
        phases[t.id] = .installing
        return app
    }

    private func finish(_ t: CatalogTool, work: URL) {
        try? FileManager.default.removeItem(at: work)
        phases[t.id] = nil
        downloads[t.id] = nil
        observations[t.id] = nil
    }

    private func report(_ error: Error, _ t: CatalogTool) {
        if let e = error as? URLError, e.code == .cancelled {
            show("Download von \(t.release.name) abgebrochen.")
        } else {
            show("\(t.release.name): \(error.localizedDescription)", error: true)
        }
    }

    /// Installiert oder aktualisiert eine App. Läuft sie, wird sie vorher regulär beendet.
    func install(_ t: CatalogTool) async {
        guard phases[t.id] == nil else { return }
        // App-Store-Apps installiert und aktualisiert ausschließlich der App Store.
        if usesAppStore(t) || !t.isDirect { return t.github != nil ? openGitHub(t) : openAppStore(t) }
        if let reason = t.unsupportedReason { return show("\(t.release.name): \(reason).", error: true) }
        let wasInstalled = installed[t.id]
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("KundidaToolbox-\(UUID().uuidString)")
        defer { finish(t, work: work) }
        do {
            let app = try await fetchVerifiedApp(t, work: work)
            if wasInstalled != nil { try await quit(t) }
            let dir = wasInstalled?.url.deletingLastPathComponent() ?? installDirectory
            try Installer.place(app, at: dir.appendingPathComponent(app.lastPathComponent), workDir: work)
            rescan()
            show(wasInstalled == nil
                 ? "\(t.release.name) \(t.release.version) wurde installiert."
                 : "\(t.release.name) wurde auf \(t.release.version) aktualisiert.")
        } catch {
            report(error, t)
        }
    }

    /// Legt die App in den Papierkorb (wiederherstellbar).
    func uninstall(_ t: CatalogTool) async {
        guard let app = installed[t.id] else { return }
        do {
            try await quit(t)
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
            rescan()
            show("\(t.release.name) wurde in den Papierkorb gelegt.")
        } catch {
            show("\(t.release.name): \(error.localizedDescription)", error: true)
        }
    }

    func show(_ text: String, error: Bool = false) {
        let n = Notice(text: text, isError: error)
        notice = n
        Task {
            try? await Task.sleep(for: .seconds(error ? 8 : 4))
            if notice == n { notice = nil }
        }
    }

    // MARK: - Hilfen

    private func runningApp(_ t: CatalogTool) -> NSRunningApplication? {
        guard let id = installed[t.id]?.bundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }

    private func quit(_ t: CatalogTool) async throws {
        guard let app = runningApp(t) else { return }
        app.terminate()
        for _ in 0..<50 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(200)) }
        if !app.isTerminated { throw ToolboxError("\(t.release.name) konnte nicht beendet werden. Bitte die App selbst beenden.") }
    }

    private func download(_ url: URL, to dest: URL, id: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
                if let error { return cont.resume(throwing: error) }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return cont.resume(throwing: ToolboxError("Download fehlgeschlagen (HTTP \(http.statusCode))."))
                }
                guard let tmp else { return cont.resume(throwing: ToolboxError("Download fehlgeschlagen.")) }
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
            observations[id] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let value = p.fractionCompleted
                Task { @MainActor in
                    if case .downloading = self?.phases[id] { self?.phases[id] = .downloading(value) }
                }
            }
            downloads[id] = task
            task.resume()
        }
    }
}
