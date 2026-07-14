import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service todo tools")
@MainActor
struct ThingsToolServiceTodoToolsTests {
  @Test("save_todo maps create and update null-clears")
  func saveTodoCreateAndUpdate() async throws {
    let repository = ThingsRepositorySpy()
    repository.token = "secret-token"
    let builder = ThingsURLBuilderSpy()
    let executor = ThingsCallbackExecutorSpy()
    let service = ThingsToolService(
      urlBuilder: builder,
      callbackExecutor: executor,
      repository: repository
    )
    let tool = try #require(service.tools().first { $0.name == "things_save_todo" })

    let createResult = try await tool([
      "title": .string("  Ship release  "),
      "notes": .string("  release notes  "),
      "tags": .array([.string("Work"), .string("Urgent")]),
      "checklist_items": .array([.string("QA"), .string("Deploy")]),
      "project": .string("Project"),
      "heading": .string("Planning"),
      "reveal": .bool(true),
    ])

    let createCall = try #require(builder.todoCalls.first)
    #expect(createCall.authToken == nil)
    #expect(createCall.request.id == nil)
    #expect(createCall.request.title == "Ship release")
    #expect(createCall.request.notes == .value("  release notes  "))
    #expect(createCall.request.tags == .value(["Work", "Urgent"]))
    #expect(createCall.request.checklistItems == .value(["QA", "Deploy"]))
    #expect(createCall.request.destination == .value("project:project-id"))
    #expect(createCall.request.heading == .value("heading:planning"))
    #expect(createCall.request.reveal)
    #expect(repository.authTokenCallCount == 0)
    #expect(createResult.objectValue?["operation"] == .string("create"))

    let updateResult = try await tool([
      "id": .string("todo:todo-id"),
      "notes": .null,
      "when": .null,
      "deadline": .null,
      "tags": .null,
      "checklist_items": .null,
      "project": .null,
      "heading": .null,
    ])

    #expect(builder.todoCalls.count == 2)
    let updateCall = builder.todoCalls[1]
    #expect(updateCall.authToken == "secret-token")
    #expect(updateCall.request.id == "todo:todo-id")
    #expect(updateCall.request.title == nil)
    #expect(updateCall.request.notes == .clear)
    #expect(updateCall.request.when == .clear)
    #expect(updateCall.request.deadline == .clear)
    #expect(updateCall.request.tags == .clear)
    #expect(updateCall.request.checklistItems == .clear)
    #expect(updateCall.request.destination == .clear)
    #expect(updateCall.request.heading == .clear)
    #expect(repository.authTokenCallCount == 1)
    #expect(executor.urls.count == 2)
    #expect(updateResult.objectValue?["operation"] == .string("update"))
    #expect(updateResult.objectValue?["ref"] == .string("todo:todo-id"))
  }

  @Test("save_todo rejects conflicting mutations before dispatch")
  func saveTodoConflictValidation() async throws {
    let builder = ThingsURLBuilderSpy()
    let executor = ThingsCallbackExecutorSpy()
    let service = ThingsToolService(
      urlBuilder: builder,
      callbackExecutor: executor,
      repository: ThingsRepositorySpy()
    )
    let tool = try #require(service.tools().first { $0.name == "things_save_todo" })

    var caughtDestinationConflict = false
    do {
      _ = try await tool([
        "title": .string("Conflicting destination"),
        "project": .string("Project"),
        "area": .string("Area"),
      ])
    } catch {
      caughtDestinationConflict = true
      #expect(error.localizedDescription.contains("project"))
      #expect(error.localizedDescription.contains("area"))
    }
    #expect(caughtDestinationConflict)

    var caughtHeadingAreaClearConflict = false
    do {
      _ = try await tool([
        "id": .string("todo:todo-id"),
        "area": .null,
        "heading": .string("Planning"),
      ])
    } catch {
      caughtHeadingAreaClearConflict = true
      #expect(error.localizedDescription.contains("heading"))
      #expect(error.localizedDescription.contains("area"))
    }
    #expect(caughtHeadingAreaClearConflict)

    var caughtNotesConflict = false
    do {
      _ = try await tool([
        "title": .string("Conflicting notes"),
        "notes": .string("replacement"),
        "append_notes": .string("append"),
      ])
    } catch {
      caughtNotesConflict = true
      #expect(error.localizedDescription.contains("notes"))
      #expect(error.localizedDescription.contains("append_notes"))
    }
    #expect(caughtNotesConflict)

    var caughtUpdateOnlyCreate = false
    do {
      _ = try await tool([
        "title": .string("Invalid create"),
        "append_notes": .string("requires an id"),
      ])
    } catch {
      caughtUpdateOnlyCreate = true
      #expect(error.localizedDescription.contains("append_notes"))
      #expect(error.localizedDescription.contains("id"))
    }
    #expect(caughtUpdateOnlyCreate)
    #expect(builder.todoCalls.isEmpty)
    #expect(executor.urls.isEmpty)
  }

  @Test("update_checklist preserves row state and maps edits to Things JSON")
  func updateChecklistMapping() async throws {
    let repository = ThingsRepositorySpy()
    repository.token = "url-token"
    repository.todo = ThingsTestFixtures.todoWithChecklist
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy(
      responses: [thingsCallback(["x-things-id": ["todo-1"]])]
    )
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_update_checklist" }
    )

    let result = try await tool([
      "id": .string("todo:todo-1"),
      "set": .array([
        .object([
          "id": .string("row-1"),
          "title": .string("Renamed"),
          "status": .string("completed"),
        ])
      ]),
      "add": .array([
        .object([
          "title": .string("New row"),
          "status": .string("canceled"),
        ])
      ]),
      "remove_ids": .array([.string("row-2")]),
      "order": .array([.string("row-1")]),
      "reveal": .bool(true),
    ])

    let request = try #require(builder.jsonRequests.first)
    #expect(request.authToken == "url-token")
    #expect(request.reveal)
    #expect(request.items.count == 1)
    guard case .todo(let operation, let id, let attributes) = request.items[0] else {
      Issue.record("Expected a todo JSON update")
      return
    }
    #expect(operation == .update)
    #expect(id == "todo-1")
    #expect(
      attributes.checklistItems == [
        ThingsJSONChecklistItem(title: "Renamed", completed: true, canceled: false),
        ThingsJSONChecklistItem(title: "New row", completed: false, canceled: true),
      ]
    )
    #expect(result.objectValue?["operation"] == .string("update_checklist"))
    #expect(result.objectValue?["ref"] == .string("todo:todo-1"))
    #expect(result.objectValue?["acknowledged"] == .bool(true))
    #expect(result.objectValue?["verified"] == .bool(false))
    #expect(result.objectValue?["confirmed"] == nil)
  }

  @Test("update_checklist rejects unknown row IDs before dispatch")
  func updateChecklistValidation() async throws {
    let repository = ThingsRepositorySpy()
    repository.todo = ThingsTestFixtures.todoWithChecklist
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_update_checklist" }
    )

    var caught = false
    do {
      _ = try await tool([
        "id": .string("todo:todo-1"),
        "remove_ids": .array([.string("missing-row")]),
      ])
    } catch {
      caught = true
      #expect(error.localizedDescription.contains("unknown checklist item id"))
    }
    #expect(caught)
    #expect(builder.jsonRequests.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("URL writes reject delimiter injection, ignored schedules, and oversized strings")
  func urlWriteContractValidation() async throws {
    let callback = ThingsCallbackExecutorSpy()
    let service = makeThingsService(callback: callback)
    let saveTodo = try #require(service.tools().first { $0.name == "things_save_todo" })
    let invalidInputs: [[String: Value]] = [
      ["titles": .array([.string("One\nTwo")])],
      ["title": .string(String(repeating: "x", count: 4_001))],
      ["title": .string("Todo"), "notes": .string(String(repeating: "n", count: 10_001))],
      ["title": .string("Todo"), "tags": .array([.string("One,Two")])],
      ["title": .string("Todo"), "when": .string("someday@09:00")],
      ["id": .string("todo:todo-1"), "when": .string("anytime")],
      ["title": .string("Todo"), "completion_date": .string("2020-01-01T00:00:00Z")],
      ["title": .string("Todo"), "creation_date": .string("2999-01-01T00:00:00Z")],
    ]

    for input in invalidInputs {
      do {
        _ = try await saveTodo(input)
        Issue.record("Expected URL contract validation to reject input")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
    }
    #expect(callback.urls.isEmpty)
  }
}
