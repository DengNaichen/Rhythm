import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

private let openClawLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "NaichengDeng.Rhythm",
  category: "integration.openClaw"
)
private let openClawConfigPath =
  "/Users/\(NSUserName())/.openclaw/workspace/config/mcporter.json"
private let openClawServerName = "Rhythm"
private let legacyOpenClawServerNames = ["iMCP"]

private let openClawEncoder: JSONEncoder = {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  return encoder
}()

private let openClawDecoder = JSONDecoder()

enum OpenClaw {
  struct Config: Codable {
    struct MCPServer: Codable {
      var command: String
      var args: [String]?
      var env: [String: String]?
    }

    var imports: [String]?
    var mcpServers: [String: MCPServer]
  }

  enum Error: LocalizedError {
    case noLocationSelected

    var errorDescription: String? {
      switch self {
      case .noLocationSelected:
        return "No location selected to save OpenClaw config."
      }
    }
  }

  @discardableResult
  static func showConfigurationPanel() -> Bool {
    do {
      let (config, rhythmServer) = try loadConfig()
      let fileExists = FileManager.default.fileExists(atPath: openClawConfigPath)

      let alert = NSAlert()
      alert.messageText = "Set Up Rhythm Server"
      alert.informativeText = """
        This will \(fileExists ? "update" : "create") the Rhythm server settings in OpenClaw.

        Location: \(openClawConfigPath)
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
      openClawLog.error("OpenClaw configuration failed: \(error.localizedDescription)")

      let alert = NSAlert()
      alert.messageText = "Configuration Error"
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .critical
      alert.runModal()
      return false
    }
  }
}

private func loadConfig() throws -> ([String: Value], OpenClaw.Config.MCPServer) {
  let rhythmServer = OpenClaw.Config.MCPServer(
    command: Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/rhythm-server")
      .path
  )

  let loadedConfiguration = try loadOpenClawConfiguration(
    bookmarkKey: BookmarkStorageKey.openClawConfig,
    defaultPath: openClawConfigPath
  )

  return (
    loadedConfiguration ?? ["imports": .array([]), "mcpServers": .object([:])],
    rhythmServer
  )
}

private func updateConfig(
  _ config: [String: Value],
  upserting rhythmServer: OpenClaw.Config.MCPServer
) throws {
  var updatedConfig = config
  var mcpServers = updatedConfig["mcpServers"]?.objectValue ?? [:]
  mcpServers[openClawServerName] = try Value(rhythmServer)

  for legacyName in legacyOpenClawServerNames where legacyName != openClawServerName {
    mcpServers.removeValue(forKey: legacyName)
  }

  updatedConfig["mcpServers"] = .object(mcpServers)

  try writeOpenClawConfiguration(
    updatedConfig,
    bookmarkKey: BookmarkStorageKey.openClawConfig,
    defaultPath: openClawConfigPath,
    defaultFilename: "mcporter.json"
  )
}

private func loadOpenClawConfiguration(
  bookmarkKey: String,
  defaultPath: String
) throws -> [String: Value]? {
  if let secureURL = try getOpenClawSecurityScopedConfigURL(bookmarkKey: bookmarkKey) {
    if secureURL.startAccessingSecurityScopedResource() {
      defer { secureURL.stopAccessingSecurityScopedResource() }

      if FileManager.default.fileExists(atPath: secureURL.path) {
        let data = try Data(contentsOf: secureURL)
        try saveOpenClawSecurityScopedAccess(for: secureURL, bookmarkKey: bookmarkKey)
        return try openClawDecoder.decode([String: Value].self, from: data)
      }
    }
  }

  let defaultURL = URL(fileURLWithPath: defaultPath)
  guard FileManager.default.fileExists(atPath: defaultURL.path) else {
    return nil
  }

  let data = try Data(contentsOf: defaultURL)
  try? saveOpenClawSecurityScopedAccess(for: defaultURL, bookmarkKey: bookmarkKey)
  return try openClawDecoder.decode([String: Value].self, from: data)
}

private func writeOpenClawConfiguration(
  _ config: [String: Value],
  bookmarkKey: String,
  defaultPath: String,
  defaultFilename: String
) throws {
  if let secureURL = try getOpenClawSecurityScopedConfigURL(bookmarkKey: bookmarkKey) {
    if secureURL.startAccessingSecurityScopedResource() {
      defer { secureURL.stopAccessingSecurityScopedResource() }

      do {
        try writeOpenClawConfig(config, to: secureURL)
        return
      } catch {
        openClawLog.error("Failed writing security scoped config: \(error.localizedDescription)")
      }
    }
  }

  let defaultURL = URL(fileURLWithPath: defaultPath)
  if FileManager.default.fileExists(atPath: defaultPath),
    FileManager.default.isWritableFile(atPath: defaultPath)
  {
    try writeOpenClawConfig(config, to: defaultURL)
    try? saveOpenClawSecurityScopedAccess(for: defaultURL, bookmarkKey: bookmarkKey)
    return
  }

  let savePanel = NSSavePanel()
  savePanel.message = "Choose where to save the Rhythm server settings for OpenClaw."
  savePanel.prompt = "Set Up"
  savePanel.allowedContentTypes = [.json]
  savePanel.directoryURL = defaultURL.deletingLastPathComponent()
  savePanel.nameFieldStringValue = defaultFilename
  savePanel.canCreateDirectories = true
  savePanel.showsHiddenFiles = true

  guard savePanel.runModal() == .OK, let selectedURL = savePanel.url else {
    throw OpenClaw.Error.noLocationSelected
  }

  try writeOpenClawConfig(config, to: selectedURL)
  try? saveOpenClawSecurityScopedAccess(for: selectedURL, bookmarkKey: bookmarkKey)
}

private func writeOpenClawConfig(_ config: [String: Value], to url: URL) throws {
  let data = try openClawEncoder.encode(config)
  let directoryURL = url.deletingLastPathComponent()

  try FileManager.default.createDirectory(
    at: directoryURL,
    withIntermediateDirectories: true
  )
  try data.write(to: url, options: .atomic)
}

private func getOpenClawSecurityScopedConfigURL(bookmarkKey: String) throws -> URL? {
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

private func saveOpenClawSecurityScopedAccess(for url: URL, bookmarkKey: String) throws {
  let bookmarkData = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
  )
  UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
}
