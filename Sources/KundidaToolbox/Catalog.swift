import Foundation

/// Team-ID der Developer ID, mit der alle Kundida-Apps signiert sein müssen.
let trustedTeamID = "LX259B8S89"
let defaultSource = "https://download.kundida.de"
/// Entwicklerkonto im App Store (für Perun, Chronorius, Bifröst …).
let appStoreDeveloperID = 6792370458

/// Aufbau von `data/releases.json` auf download.kundida.de.
struct ReleaseFeed: Decodable {
    let apps: [String: Lenient<Release>]
}

/// Ein fehlerhafter Eintrag im Katalog soll nicht den ganzen Katalog unbrauchbar machen.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Release: Codable, Equatable {
    let name: String
    let tagline: String?
    let version: String
    let build: String?
    let date: String?
    let file: String
    let size: String?
    let sha256: String
    let minOS: String?
    let arch: String?
    let notarized: Bool?
}

/// App aus dem App Store (über Apples öffentliche Lookup-Schnittstelle für das Entwicklerkonto).
struct AppStoreApp: Codable, Equatable {
    let trackId: Int
    let name: String
    let version: String
    let isMac: Bool
    let artwork: URL?
    let summary: String?
    let minOS: String?
    let releaseDate: String?
    let sizeBytes: Int?
    let releaseNotes: String?

    var storeURL: URL { URL(string: "macappstore://apps.apple.com/de/app/id\(trackId)")! }

    /// Katalogeintrag für Apps, die es nur im App Store gibt.
    var asTool: CatalogTool {
        let date = releaseDate.map { String($0.prefix(10)) }
        let size = sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let release = Release(
            name: name, tagline: summary, version: version, build: nil, date: date, file: "", size: size, sha256: "",
            minOS: isMac ? minOS.map { "macOS \($0) oder neuer" } : nil,
            arch: isMac ? nil : "iPhone-/iPad-App, läuft auf Macs mit Apple Silicon", notarized: nil)
        return CatalogTool(id: normalizedName(name), release: release, appStore: self)
    }
}

/// Kostenlose Tools auf GitHub (Name = Anzeigename, appName = Name des App-Pakets).
struct GitHubSource {
    let repo: String
    let name: String
    let appName: String
}

let githubSources = [
    GitHubSource(repo: "holgerdaehn/save_the_date", name: "Save the Date", appName: "Save the Date"),
    GitHubSource(repo: "holgerdaehn/schredder", name: "Schredder", appName: "Schredder"),
]

struct GitHubInfo: Codable, Equatable {
    let repo: String
    let appName: String
    let pageURL: URL
    let notes: String?
}

/// Kurztext unter dem App-Namen: was die App macht.
let appSummaries: [String: String] = [
    "forseti": "Pflegt deinen Mac: Updates, Bereinigung und Checks",
    "triglav": "RDP- und SSH-Verbindungen übersichtlich an einem Ort",
    "itcommandcenter": "Dein Cockpit für IT-Themen, Projekte, Meetings und Zeiten",
    "bifrost": "App Store Connect als native Mac-App",
    "vardscan": "Findet Geräte im Netzwerk und führt ein Inventar",
    "perun": "Wetter aus mehreren Modellen im direkten Vergleich",
    "chronorius": "Was an diesem Tag in der Geschichte geschah",
    "savethedate": "Ändert Datei-Zeitstempel, EXIF-Daten und GPS-Orte",
    "schredder": "Löscht Festplatten und SSDs sicher und endgültig",
]

/// "Bifröst" → "bifrost", "IT Command Center" → "itcommandcenter" (passt zu den Schlüsseln in releases.json).
func normalizedName(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de")).filter { $0.isLetter || $0.isNumber }.lowercased()
}

struct CatalogTool: Identifiable, Equatable, Codable {
    let id: String
    let release: Release
    var appStore: AppStoreApp? = nil
    var github: GitHubInfo? = nil

    /// Von der Toolbox selbst installierbar (download.kundida.de oder GitHub-Release).
    var isDirect: Bool { !release.file.isEmpty }

    var summary: String? { appSummaries[id] ?? release.tagline }

    /// Absolute Adresse (GitHub) oder Pfad relativ zur Download-Quelle.
    func downloadURL(base: URL?) -> URL? {
        if release.file.hasPrefix("https://") { return URL(string: release.file) }
        guard !release.file.contains("..") else { return nil }
        return base?.appendingPathComponent(release.file)
    }

    /// Name des App-Pakets: aus dem Dateinamen ("downloads/Forseti-1.1.5.zip" → "Forseti"), sonst App-Store-Name.
    var appName: String {
        if let github { return github.appName }
        guard isDirect else { return release.name }
        let file = (release.file as NSString).lastPathComponent
        return String(file.prefix { $0 != "-" && $0 != "." })
    }

    /// Erste Zahl aus "macOS 14 Sonoma oder neuer".
    var requiredMajorOS: Int? {
        guard let minOS = release.minOS, let r = minOS.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(minOS[r])
    }

    var appleSiliconOnly: Bool {
        let a = (release.arch ?? "").lowercased()
        return a.contains("apple silicon") && !a.contains("universal") && !a.contains("intel")
    }

    /// Grund, warum die App auf diesem Mac nicht installiert werden kann (nil = installierbar).
    var unsupportedReason: String? {
        #if !arch(arm64)
        if let a = appStore, !a.isMac, !isDirect { return "iPhone-/iPad-Apps benötigen einen Mac mit Apple Silicon" }
        #endif
        if let req = requiredMajorOS, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < req {
            return "Benötigt \(release.minOS ?? "macOS \(req)")"
        }
        #if !arch(arm64)
        if appleSiliconOnly { return "Benötigt einen Mac mit Apple Silicon" }
        #endif
        return nil
    }

    /// `build` sollte `sparkle:version` aus dem Appcast sein (entspricht CFBundleVersion).
    /// Builds werden nur verglichen, wenn sie gleich aufgebaut sind – so löst z. B.
    /// "2026.11.13.1330" gegenüber "61" kein falsches Update aus.
    func isNewer(than installed: InstalledApp, build: String?) -> Bool {
        let v = release.version.compare(installed.version, options: .numeric)
        if v != .orderedSame { return v == .orderedDescending }
        guard let build, !installed.build.isEmpty,
              build.split(separator: ".").count == installed.build.split(separator: ".").count
        else { return false }
        return build.compare(installed.build, options: .numeric) == .orderedDescending
    }
}

struct InstalledApp: Equatable {
    let url: URL
    let version: String
    let build: String
    let bundleID: String?
    /// Aus dem App Store installiert (Mac-App mit Beleg oder iPhone-/iPad-App).
    let fromAppStore: Bool

    /// Liest Info.plist direkt (Bundle(url:) würde veraltete Werte zwischenspeichern).
    static func read(at url: URL) -> InstalledApp? {
        let fm = FileManager.default
        // iPhone-/iPad-Apps auf dem Mac liegen als Wrapper vor: Perun.app/WrappedBundle/Info.plist
        let wrapped = url.appendingPathComponent("WrappedBundle/Info.plist")
        let isWrapped = fm.fileExists(atPath: wrapped.path)
        let plist = isWrapped ? wrapped : url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        return InstalledApp(
            url: url,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            bundleID: info["CFBundleIdentifier"] as? String,
            fromAppStore: isWrapped || fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        )
    }
}

/// Antwort von itunes.apple.com/lookup.
struct AppStoreLookup: Decodable {
    struct Item: Decodable {
        let wrapperType: String?
        let kind: String?
        let trackId: Int?
        let trackName: String?
        let version: String?
        let artworkUrl512: String?
        let description: String?
        let minimumOsVersion: String?
        let currentVersionReleaseDate: String?
        let fileSizeBytes: String?
        let releaseNotes: String?
    }
    let results: [Item]

    var apps: [AppStoreApp] {
        results.compactMap { r in
            guard r.wrapperType == "software", let id = r.trackId, let name = r.trackName, let version = r.version else { return nil }
            let summary = r.description?.split(whereSeparator: \.isNewline).first.map { String($0.prefix(90)) }
            return AppStoreApp(trackId: id, name: name, version: version, isMac: r.kind == "mac-software",
                               artwork: r.artworkUrl512.flatMap(URL.init(string:)), summary: summary, minOS: r.minimumOsVersion,
                               releaseDate: r.currentVersionReleaseDate, sizeBytes: r.fileSizeBytes.flatMap { Int($0) },
                               releaseNotes: r.releaseNotes)
        }
    }
}

struct ToolboxError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
