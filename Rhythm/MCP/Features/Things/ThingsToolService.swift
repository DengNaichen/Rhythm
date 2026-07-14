import AppKit
import Foundation
import JSONSchema
import OrderedCollections
import UniformTypeIdentifiers

private let thingsGroupContainerPath =
  "/Users/\(NSUserName())/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac"
private let thingsDatabaseBookmarkKey = BookmarkStorageKey.thingsDatabase

@MainActor
final class ThingsToolService: NSObject, Service, NSOpenSavePanelDelegate, ThingsDatabaseAccessing {
  let id = "things"
  let displayName = "Things"

  let urlBuilder: any ThingsURLBuilding
  let callbackExecutor: any ThingsCallbackExecuting
  let automationExecutor: any ThingsAutomationExecuting
  private let injectedRepository: (any ThingsRepository)?
  private lazy var liveRepository = ThingsStore(databaseAccess: self)

  var repository: any ThingsRepository {
    if let injectedRepository { return injectedRepository }
    return liveRepository
  }

  init(
    urlBuilder: any ThingsURLBuilding = ThingsURLBuilder(),
    callbackExecutor: any ThingsCallbackExecuting = ThingsCallbackExecutor.shared,
    automationExecutor: (any ThingsAutomationExecuting)? = nil,
    repository: (any ThingsRepository)? = nil
  ) {
    self.urlBuilder = urlBuilder
    self.callbackExecutor = callbackExecutor
    self.automationExecutor = automationExecutor ?? WorkspaceThingsAutomationExecutor()
    self.injectedRepository = repository
    super.init()
  }

  func tools() -> [Tool] {
    [
      searchTool(),
      fetchTool(),
      listTodosTool(),
      getTodoTool(),
      saveTodoTool(),
      updateChecklistTool(),
      listHeadingsTool(),
      getHeadingTool(),
      listProjectsTool(),
      getProjectTool(),
      saveProjectTool(),
      batchTool(),
      listAreasTool(),
      saveAreaTool(),
      listTagsTool(),
      saveTagTool(),
      trashTool(),
      restoreTool(),
      emptyTrashTool(),
      logCompletedTool(),
      showTool(),
      openSearchTool(),
      versionTool(),
    ]
  }

  func isActivated() async -> Bool {
    injectedRepository != nil || canAccessDatabaseAtDefaultPath || canAccessDatabaseUsingBookmark
  }

  func activate() async throws {
    if injectedRepository != nil || canAccessDatabaseAtDefaultPath || canAccessDatabaseUsingBookmark
    {
      return
    }

    guard showDatabaseAccessAlert() else {
      throw ThingsToolServiceAccessError.userDeclinedAccess
    }

    let selectedURL = try showFilePicker()
    _ = try validateSelection(selectedURL)
    try storeBookmark(for: selectedURL)
  }

  func withReadableDatabaseURL<T>(_ operation: (URL) throws -> T) throws -> T {
    if let defaultURL = defaultDatabaseURL(),
      FileManager.default.isReadableFile(atPath: defaultURL.path)
    {
      return try operation(defaultURL)
    }

    let rootURL = try resolveBookmarkURL()
    return try withSecurityScopedAccess(rootURL) { url in
      let databaseURL = try self.resolveDatabaseURL(from: url)
      guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
        throw ThingsToolServiceAccessError.databaseAccessRequired
      }
      return try operation(databaseURL)
    }
  }

  private var canAccessDatabaseAtDefaultPath: Bool {
    guard let defaultURL = defaultDatabaseURL() else { return false }
    return FileManager.default.isReadableFile(atPath: defaultURL.path)
  }

  private var canAccessDatabaseUsingBookmark: Bool {
    do {
      let rootURL = try resolveBookmarkURL()
      return try withSecurityScopedAccess(rootURL) { url in
        let databaseURL = try self.resolveDatabaseURL(from: url)
        return FileManager.default.isReadableFile(atPath: databaseURL.path)
      }
    } catch {
      return false
    }
  }

  private func defaultDatabaseURL() -> URL? {
    try? resolveDatabaseURL(from: URL(fileURLWithPath: thingsGroupContainerPath))
  }

  private func withSecurityScopedAccess<T>(
    _ url: URL,
    _ operation: (URL) throws -> T
  ) throws -> T {
    guard url.startAccessingSecurityScopedResource() else {
      throw ThingsToolServiceAccessError.securityScopeAccessFailed
    }
    defer { url.stopAccessingSecurityScopedResource() }
    return try operation(url)
  }

  private func resolveBookmarkURL() throws -> URL {
    guard let bookmarkData = UserDefaults.standard.data(forKey: thingsDatabaseBookmarkKey) else {
      throw ThingsToolServiceAccessError.databaseAccessRequired
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    if isStale { try storeBookmark(for: url) }
    return url
  }

  private func resolveDatabaseURL(from selectionURL: URL) throws -> URL {
    if selectionURL.lastPathComponent == "main.sqlite" { return selectionURL }

    if selectionURL.pathExtension == "thingsdatabase"
      || selectionURL.lastPathComponent == "Things Database.thingsdatabase"
    {
      return selectionURL.appendingPathComponent("main.sqlite")
    }

    let fileManager = FileManager.default
    if let enumerator = fileManager.enumerator(
      at: selectionURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let url as URL in enumerator {
        if url.lastPathComponent == "main.sqlite",
          url.path.contains("Things Database.thingsdatabase")
        {
          return url
        }
      }
    }
    throw ThingsToolServiceAccessError.invalidSelection
  }

  private func validateSelection(_ url: URL) throws -> URL {
    let databaseURL = try resolveDatabaseURL(from: url)
    guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
      throw ThingsToolServiceAccessError.databaseNotReadable
    }
    return databaseURL
  }

  private func showDatabaseAccessAlert() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Things Database Access Required"
    alert.informativeText = """
      To read your Things data, Rhythm needs read-only access to the Things database.

      Select the Things group container, Things Database.thingsdatabase, or main.sqlite.
      """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func showFilePicker() throws -> URL {
    let openPanel = NSOpenPanel()
    openPanel.delegate = self
    openPanel.message = "Select the Things database folder, package, or main.sqlite file"
    openPanel.prompt = "Grant Access"
    openPanel.allowedContentTypes = [UTType.item]
    openPanel.directoryURL = URL(fileURLWithPath: thingsGroupContainerPath)
      .deletingLastPathComponent()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = true
    openPanel.showsHiddenFiles = true
    openPanel.resolvesAliases = true

    guard openPanel.runModal() == .OK, let url = openPanel.url else {
      throw ThingsToolServiceAccessError.invalidSelection
    }
    return url
  }

  private func storeBookmark(for url: URL) throws {
    let bookmarkData = try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    UserDefaults.standard.set(bookmarkData, forKey: thingsDatabaseBookmarkKey)
  }

  func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
    url.hasDirectoryPath || url.lastPathComponent == "main.sqlite"
  }
}

enum ThingsToolServiceAccessError: Error, LocalizedError {
  case databaseAccessRequired
  case securityScopeAccessFailed
  case userDeclinedAccess
  case invalidSelection
  case databaseNotReadable

  var errorDescription: String? {
    switch self {
    case .databaseAccessRequired:
      return "Things database access is required."
    case .securityScopeAccessFailed:
      return "Failed to access the selected Things database location."
    case .userDeclinedAccess:
      return "User declined to grant access to the Things database."
    case .invalidSelection:
      return "Invalid Things database selection."
    case .databaseNotReadable:
      return "The selected Things database is not readable."
    }
  }
}
