import Foundation

/// Neuester Eintrag aus `appcast/<id>.xml` (Sparkle-Format).
/// `sparkle:version` entspricht CFBundleVersion der App und ist damit die verlässliche Build-Referenz.
struct AppcastInfo: Codable, Equatable {
    var build: String?
    var shortVersion: String?
    var notes: String?
    var notesURL: URL?

    static func parse(_ data: Data) -> AppcastInfo? {
        let p = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.shouldProcessNamespaces = false
        guard xml.parse() || p.info.build != nil, p.info != AppcastInfo() else { return nil }
        var info = p.info
        info.notes = info.notes.flatMap(plainText)
        return info
    }

    /// Wandelt HTML-Versionshinweise in lesbaren Text um (ohne WebKit, daher auch abseits des Main-Threads nutzbar).
    static func plainText(_ s: String) -> String? {
        var t = s
        for (pattern, repl) in [(#"(?i)<li[^>]*>"#, "\n• "), (#"(?i)<br\s*/?>|</p>|</h\d>|</li>"#, "\n"), (#"<[^>]+>"#, "")] {
            t = t.replacingOccurrences(of: pattern, with: repl, options: .regularExpression)
        }
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        t = t.replacingOccurrences(of: #"\n[ \t]*\n+"#, with: "\n", options: .regularExpression)
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Macht GitHub-Markdown lesbar (Überschriften, Fettdruck, Aufzählungen).
    static func markdownText(_ s: String) -> String? {
        var t = s
        for (pattern, repl) in [(#"(?m)^#{1,6}\s*"#, ""), (#"\*\*([^*]+)\*\*"#, "$1"), (#"(?m)^\s*[-*]\s+"#, "• "), (#"\[([^\]]+)\]\([^)]+\)"#, "$1")] {
            t = t.replacingOccurrences(of: pattern, with: repl, options: .regularExpression)
        }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Liest nur das erste <item> (neueste Version).
    private final class Parser: NSObject, XMLParserDelegate {
        var info = AppcastInfo()
        private var inItem = false
        private var done = false
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard !done else { return }
            if name == "item" { inItem = true }
            text = ""
            if inItem, name == "enclosure" {
                info.build = info.build ?? attributes["sparkle:version"]
                info.shortVersion = info.shortVersion ?? attributes["sparkle:shortVersionString"]
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(data: block, encoding: .utf8) ?? "" }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard inItem, !done else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version": info.build = value
            case "sparkle:shortVersionString": info.shortVersion = value
            case "description": info.notes = value
            case "sparkle:releaseNotesLink":
                if let url = URL(string: value), url.scheme == "https" || url.scheme == "http" { info.notesURL = url }
            case "item": done = true; parser.abortParsing()
            default: break
            }
        }
    }
}
