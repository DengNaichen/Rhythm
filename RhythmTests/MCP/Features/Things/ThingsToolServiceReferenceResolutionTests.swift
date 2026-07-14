import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service reference resolution")
@MainActor
struct ThingsToolServiceReferenceResolutionTests {
  @Test("normalizes container titles to typed IDs before URL writes")
  func writeDestinationTitleNormalization() async throws {
    let repository = ThingsRepositorySpy()
    let builder = ThingsURLBuilderSpy()
    let service = ThingsToolService(
      urlBuilder: builder,
      callbackExecutor: ThingsCallbackExecutorSpy(),
      repository: repository
    )

    let saveTodo = try #require(service.tools().first { $0.name == "things_save_todo" })
    _ = try await saveTodo([
      "title": .string("Area task"),
      "area": .string("Work"),
    ])
    #expect(builder.todoCalls.first?.request.destination == .value("area:area-id"))

    let saveProject = try #require(service.tools().first { $0.name == "things_save_project" })
    _ = try await saveProject([
      "title": .string("Area project"),
      "area": .string("Work"),
    ])
    #expect(builder.projectCalls.first?.request.area == .value("area:area-id"))
  }

  @Test("batch validates typed container, heading, and area references")
  func batchTypedReferenceValidation() async throws {
    let repository = referenceThingsRepository()
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy(
      responses: [thingsCallback(["x-things-ids": ["[\"todo-new\",\"project-new\"]"]])]
    )
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_batch" }
    )

    let result = try await tool([
      "items": .array([
        .object([
          "type": .string("to-do"),
          "attributes": .object([
            "title": .string("Scoped todo"),
            "list-id": .string("project:project-1"),
            "heading-id": .string("heading:heading-1"),
          ]),
        ]),
        .object([
          "type": .string("project"),
          "attributes": .object([
            "title": .string("Scoped project"),
            "area-id": .string("area:area-1"),
          ]),
        ]),
      ])
    ])

    let request = try #require(builder.jsonRequests.first)
    guard case .todo(_, _, let todo) = request.items[0],
      case .project(_, _, let project) = request.items[1]
    else {
      Issue.record("Expected typed todo and project batch items")
      return
    }
    #expect(todo.listID == "project:project-1")
    #expect(todo.headingID == "heading:heading-1")
    #expect(project.areaID == "area:area-1")
    #expect(result.objectValue?["acknowledged"] == .bool(true))
    #expect(result.objectValue?["verified"] == .bool(false))

    let invalidCases: [(item: Value, message: String)] = [
      (
        batchTodoValue(listID: "project:missing"),
        "No Things entity found"
      ),
      (
        batchTodoValue(listID: "tag:existing"),
        "expected a project or area ID"
      ),
      (
        batchTodoValue(
          listID: "project:project-1",
          headingID: "heading:missing"
        ),
        "No Things entity found"
      ),
      (
        batchTodoValue(
          listID: "project:project-1",
          headingID: "project:project-1"
        ),
        "expected a heading ID or title"
      ),
      (
        batchTodoValue(
          listID: "project:project-2",
          headingID: "heading:heading-1"
        ),
        "does not belong to the selected project"
      ),
      (
        batchProjectValue(areaID: "area:missing"),
        "No Things entity found"
      ),
      (
        batchProjectValue(areaID: "project:project-1"),
        "expected an area ID or title"
      ),
    ]

    for invalidCase in invalidCases {
      let invalidBuilder = ThingsURLBuilderSpy()
      let invalidCallback = ThingsCallbackExecutorSpy()
      let invalidTool = try #require(
        makeThingsService(
          repository: referenceThingsRepository(),
          builder: invalidBuilder,
          callback: invalidCallback
        ).tools().first { $0.name == "things_batch" }
      )
      do {
        _ = try await invalidTool(["items": .array([invalidCase.item])])
        Issue.record("Expected typed reference validation to fail")
      } catch {
        #expect(error.localizedDescription.contains(invalidCase.message))
      }
      #expect(invalidBuilder.jsonRequests.isEmpty)
      #expect(invalidCallback.urls.isEmpty)
    }
  }
}
