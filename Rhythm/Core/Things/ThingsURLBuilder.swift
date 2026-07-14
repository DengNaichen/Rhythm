import AppKit
import Foundation

nonisolated protocol ThingsURLBuilding {
  func saveTodoURL(for request: ThingsTodoSaveRequest, authToken: String?) throws -> URL
  func saveTodoURL(
    for request: ThingsTodoSaveRequest,
    authToken: String?,
    options: ThingsTodoURLCommandOptions
  ) throws -> URL
  func saveProjectURL(for request: ThingsProjectSaveRequest, authToken: String?) throws -> URL
  func saveProjectURL(
    for request: ThingsProjectSaveRequest,
    authToken: String?,
    options: ThingsProjectURLCommandOptions
  ) throws -> URL
  func showURL(id: String, filterTags: [String]?) throws -> URL
  func showURL(
    id: String,
    filterTags: [String]?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL
  func showURL(
    query: String,
    filterTags: [String]?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL
  func searchURL(query: String?, callbacks: ThingsURLCallbacks?) throws -> URL
  func versionURL(callbacks: ThingsURLCallbacks?) throws -> URL
  func jsonURL(for request: ThingsJSONCommandRequest) throws -> URL
}

nonisolated protocol ThingsURLExecuting {
  func execute(_ url: URL) throws
}

nonisolated enum ThingsURLBuilderError: Error, LocalizedError {
  case invalidURL
  case failedToOpen(command: String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Failed to build a Things URL."
    case .failedToOpen(let command):
      return "Failed to open the Things \(command) URL."
    }
  }
}

nonisolated struct ThingsURLBuilder: ThingsURLBuilding {}

nonisolated struct WorkspaceThingsURLExecutor: ThingsURLExecuting {
  func execute(_ url: URL) throws {
    guard NSWorkspace.shared.open(url) else {
      let command = url.pathComponents.last ?? "command"
      throw ThingsURLBuilderError.failedToOpen(command: command)
    }
  }
}
