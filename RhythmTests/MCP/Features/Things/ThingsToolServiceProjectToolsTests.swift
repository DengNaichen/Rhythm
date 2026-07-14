import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service project tools")
@MainActor
struct ThingsToolServiceProjectToolsTests {
  @Test("save_project maps create parameters and reports acknowledged but unverified")
  func saveProjectMappingAndAcknowledgement() async throws {
    let repository = ThingsRepositorySpy()
    repository.tags = [ThingsTestFixtures.existingTag]
    repository.fetchedEntities["area:area-1"] = .area(ThingsTestFixtures.area)
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy(
      responses: [thingsCallback(["x-things-id": ["project-new"]])]
    )
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_save_project" }
    )

    let result = try await tool([
      "title": .string("Launch"),
      "notes": .string("Brief"),
      "when": .string("someday"),
      "deadline": .string("2026-08-01"),
      "tags": .array([.string("Existing")]),
      "area": .string("area:area-1"),
      "initial_todos": .array([.string("Plan"), .string("Ship")]),
      "status": .string("completed"),
      "creation_date": .string("2020-07-13T10:00:00Z"),
      "completion_date": .string("2020-07-13T12:00:00Z"),
      "reveal": .bool(true),
    ])

    let call = try #require(builder.projectCalls.first)
    #expect(call.authToken == nil)
    #expect(call.request.id == nil)
    #expect(call.request.title == "Launch")
    #expect(call.request.notes == .value("Brief"))
    #expect(call.request.when == .value("someday"))
    #expect(call.request.deadline == .value("2026-08-01"))
    #expect(call.request.tags == .value(["Existing"]))
    #expect(call.request.area == .value("area:area-1"))
    #expect(call.request.status == .completed)
    #expect(call.request.reveal)
    #expect(call.options.initialTodos == ["Plan", "Ship"])
    #expect(call.options.creationDate == "2020-07-13T10:00:00Z")
    #expect(call.options.completionDate == "2020-07-13T12:00:00Z")
    #expect(result.objectValue?["operation"] == .string("create"))
    #expect(result.objectValue?["ref"] == .string("project:project-new"))
    #expect(result.objectValue?["acknowledged"] == .bool(true))
    #expect(result.objectValue?["verified"] == .bool(false))
    #expect(result.objectValue?["confirmed"] == nil)
  }
}
