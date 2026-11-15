import CryptoKit
import Foundation
import Security

/// Prüfen, Entpacken und Ablegen heruntergeladener Apps.
enum Installer {
    static func verifyChecksum(_ file: URL, expected: String) async throws {
        let actual = try await Task.detached {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.value
        guard actual == expected.lowercased() else {
            throw ToolboxError("Prüfsumme stimmt nicht überein. Der Download wurde verworfen.")
        }
    }

    static func unzip(_ zip: URL, to dir: URL) async throws {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zip.path, dir.path]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw ToolboxError("Entpacken fehlgeschlagen. \(msg)")
            }
        }.value
    }

    static func findApp(in dir: URL) throws -> URL {
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else {
            throw ToolboxError("Im Archiv wurde keine App gefunden.")
        }
        return app
    }

    /// Die App muss gültig signiert sein; mit `teamID` zusätzlich mit genau dieser Developer ID.
    static func verifySignature(_ app: URL, teamID: String?) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw ToolboxError("Die Signatur der App konnte nicht gelesen werden.")
        }
        var requirement: SecRequirement?
        if let teamID {
            let req = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
            guard SecRequirementCreateWithString(req as CFString, [], &requirement) == errSecSuccess else {
                throw ToolboxError("Signaturprüfung nicht möglich.")
            }
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate))
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            throw ToolboxError("Signaturprüfung fehlgeschlagen (Code \(status)). Die App wurde nicht installiert.")
        }
    }

    /// Legt die App am Ziel ab. Eine vorhandene Version wird erst entfernt, wenn die neue sicher liegt.
    static func place(_ app: URL, at target: URL, workDir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = workDir.appendingPathComponent("vorherige-\(target.lastPathComponent)")
        let hadOld = fm.fileExists(atPath: target.path)
        do {
            if hadOld { try fm.moveItem(at: target, to: backup) }
            try fm.moveItem(at: app, to: target)
        } catch {
            if hadOld, !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: backup, to: target) }
            throw ToolboxError("Keine Schreibrechte für \(target.deletingLastPathComponent().path). In den Einstellungen kann „Benutzer-Programme“ gewählt werden.")
        }
    }
}
