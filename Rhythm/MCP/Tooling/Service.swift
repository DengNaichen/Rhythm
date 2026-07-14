import Foundation

@MainActor
protocol Service: AnyObject {
  var id: String { get }
  var displayName: String { get }

  func tools() -> [Tool]
  func isActivated() async -> Bool
  func activate() async throws
}

extension Service {
  func tools() -> [Tool] {
    []
  }

  func isActivated() async -> Bool {
    true
  }

  func activate() async throws {}

  func call(tool name: String, with arguments: [String: Value]) async throws -> Value? {
    guard let tool = tools().first(where: { $0.name == name }) else {
      return nil
    }

    return try await tool(arguments)
  }
}
