import Foundation

@testable import Rhythm

final class ThingsURLBuilderSpy: ThingsURLBuilding {
  nonisolated(unsafe) var todoCalls:
    [(
      request: ThingsTodoSaveRequest,
      authToken: String?,
      options: ThingsTodoURLCommandOptions
    )] = []
  nonisolated(unsafe) var projectCalls:
    [(
      request: ThingsProjectSaveRequest,
      authToken: String?,
      options: ThingsProjectURLCommandOptions
    )] = []
  nonisolated(unsafe) var jsonRequests: [ThingsJSONCommandRequest] = []
  nonisolated(unsafe) var showCalls: [(id: String, filterTags: [String]?)] = []
  nonisolated(unsafe) var showIDs: [String] = []
  nonisolated(unsafe) var searchQueries: [String?] = []
  nonisolated(unsafe) var versionCallCount = 0

  nonisolated func saveTodoURL(
    for request: ThingsTodoSaveRequest,
    authToken: String?
  ) throws -> URL {
    try saveTodoURL(
      for: request,
      authToken: authToken,
      options: ThingsTodoURLCommandOptions()
    )
  }

  nonisolated func saveTodoURL(
    for request: ThingsTodoSaveRequest,
    authToken: String?,
    options: ThingsTodoURLCommandOptions
  ) throws -> URL {
    todoCalls.append((request, authToken, options))
    return URL(string: "things:///test-todo")!
  }

  nonisolated func saveProjectURL(
    for request: ThingsProjectSaveRequest,
    authToken: String?
  ) throws -> URL {
    try saveProjectURL(
      for: request,
      authToken: authToken,
      options: ThingsProjectURLCommandOptions()
    )
  }

  nonisolated func saveProjectURL(
    for request: ThingsProjectSaveRequest,
    authToken: String?,
    options: ThingsProjectURLCommandOptions
  ) throws -> URL {
    projectCalls.append((request, authToken, options))
    return URL(string: "things:///test-project")!
  }

  nonisolated func showURL(id: String, filterTags: [String]?) throws -> URL {
    showCalls.append((id, filterTags))
    showIDs.append(id)
    return URL(string: "things:///test-show")!
  }

  nonisolated func showURL(
    id: String,
    filterTags: [String]?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL {
    try showURL(id: id, filterTags: filterTags)
  }

  nonisolated func showURL(
    query: String,
    filterTags: [String]?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL {
    URL(string: "things:///test-quick-find")!
  }

  nonisolated func searchURL(
    query: String?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL {
    searchQueries.append(query)
    return URL(string: "things:///test-search")!
  }

  nonisolated func versionURL(callbacks: ThingsURLCallbacks?) throws -> URL {
    versionCallCount += 1
    return URL(string: "things:///test-version")!
  }

  nonisolated func jsonURL(for request: ThingsJSONCommandRequest) throws -> URL {
    jsonRequests.append(request)
    return URL(string: "things:///test-json")!
  }
}

final class ThingsCallbackExecutorSpy: ThingsCallbackExecuting, @unchecked Sendable {
  nonisolated(unsafe) var urls: [URL] = []
  nonisolated(unsafe) var responses: [ThingsCallbackSuccess]

  nonisolated init(responses: [ThingsCallbackSuccess] = []) {
    self.responses = responses
  }

  nonisolated func execute(_ commandURL: URL) async throws -> ThingsCallbackSuccess {
    urls.append(commandURL)
    if !responses.isEmpty {
      return responses.removeFirst()
    }
    return ThingsCallbackSuccess(requestID: UUID(), parameters: [:])
  }
}
