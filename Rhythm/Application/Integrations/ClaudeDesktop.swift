import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

private let claudeDesktopLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "NaichengDeng.Rhythm",
    category: "integration.claudeDesktop"
)
private let claudeDesktopConfigPath =
    "/Users/\(NSUserName())/Library/Application Support/Claude/claude_desktop_config.json"
private let claudeDesktopServerName = "Rhythm"
private let legacyClaudeDesktopServerNames = ["iMCP"]

private let claudeDesktopEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

private let claudeDesktopDecoder = JSONDecoder()

enum ClaudeDesktop {
    struct Config: Codable {
        struct MCPServer: Codable {
            var command: String
            var args: [String]?
            var env: [String: String]?
        }

        var mcpServers: [String: MCPServer]
    }

    enum Error: LocalizedError {
        case noLocationSelected

        var errorDescription: String? {
            switch self {
            case .noLocationSelected:
                return "No location selected to save Claude Desktop config."
            }
        }
    }

    @discardableResult
    static func showConfigurationPanel() -> Bool {
        do {
            let (config, rhythmServer) = try loadConfig()
            let fileExists = FileManager.default.fileExists(atPath: claudeDesktopConfigPath)

            let alert = NSAlert()
            alert.messageText = "Set Up Rhythm Server"
            alert.informativeText = """
                This will \(fileExists ? "update" : "create") the Rhythm server settings in Claude Desktop.

                Location: \(claudeDesktopConfigPath)
                """
            alert.addButton(withTitle: "Set Up")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)

            guard alert.runModal() == .alertFirstButtonReturn else {
                return false
            }

            try updateConfig(config, upserting: rhythmServer)
            return true
        } catch {
            claudeDesktopLog.error("Claude Desktop configuration failed: \(error.localizedDescription)")

            let alert = NSAlert()
            alert.messageText = "Configuration Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return false
        }
    }
}

private func loadConfig() throws -> ([String: Value], ClaudeDesktop.Config.MCPServer) {
    let rhythmServer = ClaudeDesktop.Config.MCPServer(
        command: Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/rhythm-server")
            .path
    )

    let loadedConfiguration = try loadConfiguration(
        bookmarkKey: BookmarkStorageKey.claudeDesktopConfig,
        defaultPath: claudeDesktopConfigPath
    )

    return (
        loadedConfiguration ?? ["mcpServers": .object([:])],
        rhythmServer
    )
}

private func updateConfig(
    _ config: [String: Value],
    upserting rhythmServer: ClaudeDesktop.Config.MCPServer
) throws {
    var updatedConfig = config
    var mcpServers = updatedConfig["mcpServers"]?.objectValue ?? [:]
    mcpServers[claudeDesktopServerName] = try Value(rhythmServer)

    for legacyName in legacyClaudeDesktopServerNames where legacyName != claudeDesktopServerName {
        mcpServers.removeValue(forKey: legacyName)
    }

    updatedConfig["mcpServers"] = .object(mcpServers)

    try writeConfiguration(
        updatedConfig,
        bookmarkKey: BookmarkStorageKey.claudeDesktopConfig,
        defaultPath: claudeDesktopConfigPath,
        defaultFilename: "claude_desktop_config.json"
    )
}

private func loadConfiguration(
    bookmarkKey: String,
    defaultPath: String
) throws -> [String: Value]? {
    if let secureURL = try getSecurityScopedConfigURL(bookmarkKey: bookmarkKey) {
        if secureURL.startAccessingSecurityScopedResource() {
            defer { secureURL.stopAccessingSecurityScopedResource() }

            if FileManager.default.fileExists(atPath: secureURL.path) {
                let data = try Data(contentsOf: secureURL)
                try saveSecurityScopedAccess(for: secureURL, bookmarkKey: bookmarkKey)
                return try claudeDesktopDecoder.decode([String: Value].self, from: data)
            }
        }
    }

    let defaultURL = URL(fileURLWithPath: defaultPath)
    guard FileManager.default.fileExists(atPath: defaultURL.path) else {
        return nil
    }

    let data = try Data(contentsOf: defaultURL)
    try? saveSecurityScopedAccess(for: defaultURL, bookmarkKey: bookmarkKey)
    return try claudeDesktopDecoder.decode([String: Value].self, from: data)
}

private func writeConfiguration(
    _ config: [String: Value],
    bookmarkKey: String,
    defaultPath: String,
    defaultFilename: String
) throws {
    if let secureURL = try getSecurityScopedConfigURL(bookmarkKey: bookmarkKey) {
        if secureURL.startAccessingSecurityScopedResource() {
            defer { secureURL.stopAccessingSecurityScopedResource() }

            do {
                try writeConfig(config, to: secureURL)
                return
            } catch {
                claudeDesktopLog.error("Failed writing security scoped config: \(error.localizedDescription)")
            }
        }
    }

    let defaultURL = URL(fileURLWithPath: defaultPath)
    if FileManager.default.fileExists(atPath: defaultPath),
        FileManager.default.isWritableFile(atPath: defaultPath)
    {
        try writeConfig(config, to: defaultURL)
        try? saveSecurityScopedAccess(for: defaultURL, bookmarkKey: bookmarkKey)
        return
    }

    let savePanel = NSSavePanel()
    savePanel.message = "Choose where to save the Rhythm server settings."
    savePanel.prompt = "Set Up"
    savePanel.allowedContentTypes = [.json]
    savePanel.directoryURL = defaultURL.deletingLastPathComponent()
    savePanel.nameFieldStringValue = defaultFilename
    savePanel.canCreateDirectories = true
    savePanel.showsHiddenFiles = true

    guard savePanel.runModal() == .OK, let selectedURL = savePanel.url else {
        throw ClaudeDesktop.Error.noLocationSelected
    }

    try writeConfig(config, to: selectedURL)
    try? saveSecurityScopedAccess(for: selectedURL, bookmarkKey: bookmarkKey)
}

private func writeConfig(_ config: [String: Value], to url: URL) throws {
    let data = try claudeDesktopEncoder.encode(config)
    let directoryURL = url.deletingLastPathComponent()

    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func getSecurityScopedConfigURL(bookmarkKey: String) throws -> URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
        return nil
    }

    var isStale = false
    return try URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )
}

private func saveSecurityScopedAccess(for url: URL, bookmarkKey: String) throws {
    let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
}
