import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service batch tool")
@MainActor
struct ThingsToolServiceBatchToolTests {
  @Test("batch maps nested JSON, authenticates updates, and returns created refs")
  func batchMapping() async throws {
    let repository = ThingsRepositorySpy()
    repository.token = "batch-token"
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy(
      responses: [thingsCallback(["x-things-ids": ["[\"project-new\"]"]])]
    )
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_batch" }
    )

    let result = try await tool([
      "items": .array([
        .object([
          "type": .string("project"),
          "attributes": .object([
            "title": .string("Launch"),
            "items": .array([
              .object([
                "type": .string("heading"),
                "attributes": .object(["title": .string("Plan")]),
              ]),
              .object([
                "type": .string("to-do"),
                "attributes": .object(["title": .string("Ship")]),
              ]),
            ]),
          ]),
        ]),
        .object([
          "type": .string("to-do"),
          "operation": .string("update"),
          "id": .string("todo:existing"),
          "attributes": .object(["append-notes": .string("Done")]),
        ]),
      ]),
      "reveal": .bool(true),
    ])

    let request = try #require(builder.jsonRequests.first)
    #expect(request.authToken == "batch-token")
    #expect(request.reveal)
    #expect(request.items.count == 2)
    guard case .project(let createOperation, let createID, let project) = request.items[0]
    else {
      Issue.record("Expected first batch item to be a project")
      return
    }
    #expect(createOperation == .create)
    #expect(createID == nil)
    #expect(project.title == "Launch")
    #expect(project.items?.count == 2)
    guard case .todo(let updateOperation, let updateID, let todo) = request.items[1] else {
      Issue.record("Expected second batch item to be a todo update")
      return
    }
    #expect(updateOperation == .update)
    #expect(updateID == "todo:existing")
    #expect(todo.appendNotes == "Done")
    #expect(result.objectValue?["operation_count"] == .int(2))
    #expect(result.objectValue?["created_count"] == .int(1))
    #expect(result.objectValue?["refs"] == .array([.string("project:project-new")]))
  }
}
