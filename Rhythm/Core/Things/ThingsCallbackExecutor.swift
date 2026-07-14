import AppKit
import Foundation

nonisolated protocol ThingsCallbackURLOpening: Sendable {
  func open(_ url: URL) async -> Bool
}

nonisolated protocol ThingsCallbackExecuting: Sendable {
  func execute(_ commandURL: URL) async throws -> ThingsCallbackSuccess
  func execute(_ commandURL: URL, timeout: Duration?) async throws -> ThingsCallbackSuccess
}

nonisolated extension ThingsCallbackExecuting {
  func execute(_ commandURL: URL, timeout: Duration?) async throws -> ThingsCallbackSuccess {
    try await execute(commandURL)
  }
}

nonisolated struct WorkspaceThingsCallbackURLOpener: ThingsCallbackURLOpening {
  func open(_ url: URL) async -> Bool {
    await MainActor.run {
      NSWorkspace.shared.open(url)
    }
  }
}

nonisolated struct ThingsCallbackSuccess: Equatable, Sendable {
  let requestID: UUID
  let parameters: [String: [String]]

  var thingsIDs: [String] {
    var ids: [String] = []

    for value in parameters["x-things-id"] ?? [] {
      ids.append(
        contentsOf:
          value
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    }

    for value in parameters["x-things-ids"] ?? [] {
      guard let data = value.data(using: .utf8),
        let decoded = try? JSONDecoder().decode([String].self, from: data)
      else { continue }
      ids.append(contentsOf: decoded)
    }

    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
  }
}

nonisolated enum ThingsCallbackExecutorError: Error, Equatable, LocalizedError, Sendable {
  case invalidCommandURL
  case failedToOpen
  case timedOut
  case tooManyPendingRequests
  case canceledByThings
  case thingsError(code: String?, message: String?)

  var errorDescription: String? {
    switch self {
    case .invalidCommandURL:
      return "The Things command URL is invalid."
    case .failedToOpen:
      return "Failed to open the Things command."
    case .timedOut:
      return
        "Things did not return a callback before the request timed out. The outcome is unknown; check Things before retrying."
    case .tooManyPendingRequests:
      return "Too many Things callback requests are pending."
    case .canceledByThings:
      return "The Things command was canceled."
    case .thingsError(let code, let message):
      let detail = [code, message]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ": ")
      return detail.isEmpty
        ? "Things rejected the command." : "Things rejected the command: \(detail)"
    }
  }
}

actor ThingsCallbackExecutor: ThingsCallbackExecuting {
  static let shared = ThingsCallbackExecutor()

  private enum Route: String {
    case success
    case error
    case cancel
  }

  private struct PendingRequest {
    let continuation: AsyncThrowingStream<ThingsCallbackSuccess, Error>.Continuation
    var openTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
  }

  private static let requestIDParameter = "rhythm-request-id"
  private static let callbackParameterNames = Set([
    "x-success", "x-error", "x-cancel", "x-source",
  ])

  private let callbackScheme: String
  private let callbackHost: String
  private let defaultTimeout: Duration
  private let maximumPendingRequests: Int
  private let opener: any ThingsCallbackURLOpening
  private var pendingRequests: [UUID: PendingRequest] = [:]

  init(
    callbackScheme: String = "rhythm-mcp",
    callbackHost: String = "things-callback",
    defaultTimeout: Duration = .seconds(45),
    maximumPendingRequests: Int = 128,
    opener: any ThingsCallbackURLOpening = WorkspaceThingsCallbackURLOpener()
  ) {
    self.callbackScheme = callbackScheme.lowercased()
    self.callbackHost = callbackHost.lowercased()
    self.defaultTimeout = defaultTimeout
    self.maximumPendingRequests = maximumPendingRequests
    self.opener = opener
  }

  func execute(_ commandURL: URL) async throws -> ThingsCallbackSuccess {
    try await execute(commandURL, timeout: nil)
  }

  func execute(
    _ commandURL: URL,
    timeout: Duration?
  ) async throws -> ThingsCallbackSuccess {
    try Task.checkCancellation()
    guard pendingRequests.count < maximumPendingRequests else {
      throw ThingsCallbackExecutorError.tooManyPendingRequests
    }

    let requestID = UUID()
    let wrappedURL = try commandURLWithCallbacks(commandURL, requestID: requestID)
    let (stream, continuation) = AsyncThrowingStream<ThingsCallbackSuccess, Error>.makeStream()
    pendingRequests[requestID] = PendingRequest(continuation: continuation)
    defer { removePendingRequest(requestID) }

    let openTask = Task { [weak self, opener] in
      guard !Task.isCancelled else { return }
      guard await opener.open(wrappedURL) else {
        await self?.fail(requestID, with: ThingsCallbackExecutorError.failedToOpen)
        return
      }
    }
    pendingRequests[requestID]?.openTask = openTask

    let requestTimeout = timeout ?? defaultTimeout
    let timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: requestTimeout)
      } catch {
        return
      }
      await self?.fail(requestID, with: ThingsCallbackExecutorError.timedOut)
    }
    pendingRequests[requestID]?.timeoutTask = timeoutTask

    return try await withTaskCancellationHandler {
      return try await firstValue(from: stream)
    } onCancel: {
      continuation.finish(throwing: CancellationError())
    }
  }

  @discardableResult
  func handle(_ callbackURL: URL) -> Bool {
    guard let callback = parseCallbackURL(callbackURL) else { return false }
    guard let pending = pendingRequests.removeValue(forKey: callback.requestID) else {
      // It is still one of our callback URLs, but the request may have timed out.
      return true
    }

    pending.timeoutTask?.cancel()
    pending.openTask?.cancel()
    let publicParameters = callback.parameters.filter { key, _ in
      key != Self.requestIDParameter
    }

    switch callback.route {
    case .success:
      pending.continuation.yield(
        ThingsCallbackSuccess(
          requestID: callback.requestID,
          parameters: publicParameters
        )
      )
      pending.continuation.finish()
    case .error:
      pending.continuation.finish(
        throwing: ThingsCallbackExecutorError.thingsError(
          code: Self.firstParameter(
            in: callback.parameters,
            named: ["errorCode", "error-code", "error_code"]
          ),
          message: Self.firstParameter(
            in: callback.parameters,
            named: ["errorMessage", "error-message", "error_message"]
          )
        )
      )
    case .cancel:
      pending.continuation.finish(throwing: ThingsCallbackExecutorError.canceledByThings)
    }
    return true
  }

  private func firstValue(
    from stream: AsyncThrowingStream<ThingsCallbackSuccess, Error>
  ) async throws -> ThingsCallbackSuccess {
    for try await value in stream {
      return value
    }
    throw CancellationError()
  }

  private func commandURLWithCallbacks(_ commandURL: URL, requestID: UUID) throws -> URL {
    guard var components = URLComponents(url: commandURL, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == "things"
    else {
      throw ThingsCallbackExecutorError.invalidCommandURL
    }

    var queryItems = (components.queryItems ?? []).filter {
      !Self.callbackParameterNames.contains($0.name.lowercased())
    }
    queryItems.append(
      contentsOf: [
        URLQueryItem(name: "x-source", value: "Rhythm"),
        URLQueryItem(
          name: "x-success",
          value: try callbackURL(route: .success, requestID: requestID).absoluteString
        ),
        URLQueryItem(
          name: "x-error",
          value: try callbackURL(route: .error, requestID: requestID).absoluteString
        ),
        URLQueryItem(
          name: "x-cancel",
          value: try callbackURL(route: .cancel, requestID: requestID).absoluteString
        ),
      ]
    )
    components.queryItems = queryItems

    guard let url = components.url else {
      throw ThingsCallbackExecutorError.invalidCommandURL
    }
    return url
  }

  private func callbackURL(route: Route, requestID: UUID) throws -> URL {
    var components = URLComponents()
    components.scheme = callbackScheme
    components.host = callbackHost
    components.path = "/\(route.rawValue)"
    components.queryItems = [
      URLQueryItem(name: Self.requestIDParameter, value: requestID.uuidString)
    ]
    guard let url = components.url else {
      throw ThingsCallbackExecutorError.invalidCommandURL
    }
    return url
  }

  private func parseCallbackURL(_ url: URL) -> (
    route: Route,
    requestID: UUID,
    parameters: [String: [String]]
  )? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == callbackScheme,
      components.host?.lowercased() == callbackHost,
      let route = Route(
        rawValue: components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    else { return nil }

    let parameters = Dictionary(grouping: components.queryItems ?? [], by: \.name)
      .mapValues { items in items.compactMap(\.value) }
    guard let requestIDValue = parameters[Self.requestIDParameter]?.first,
      let requestID = UUID(uuidString: requestIDValue)
    else { return nil }
    return (route, requestID, parameters)
  }

  private func fail(_ requestID: UUID, with error: Error) {
    guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
    pending.timeoutTask?.cancel()
    pending.openTask?.cancel()
    pending.continuation.finish(throwing: error)
  }

  private func removePendingRequest(_ requestID: UUID) {
    guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
    pending.timeoutTask?.cancel()
    pending.openTask?.cancel()
    pending.continuation.finish()
  }

  private nonisolated static func firstParameter(
    in parameters: [String: [String]],
    named names: [String]
  ) -> String? {
    for name in names {
      if let value = parameters[name]?.first { return value }
    }
    return nil
  }
}
