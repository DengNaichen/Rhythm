import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service write support")
@MainActor
struct ThingsToolServiceWriteSupportTests {
  @Test("write tools enforce Things collection limits at runtime")
  func writeCollectionLimits() async throws {
    let repository = ThingsRepositorySpy()
    repository.todo = ThingsTestFixtures.todoWithChecklist
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let service = makeThingsService(repository: repository, builder: builder, callback: callback)

    let checklist = try #require(
      service.tools().first { $0.name == "things_update_checklist" })
    let additions = (0..<99).map { index in
      Value.object(["title": .string("Row \(index)")])
    }
    do {
      _ = try await checklist([
        "id": .string("todo:todo-1"), "add": .array(additions),
      ])
      Issue.record("Expected final checklist limit validation")
    } catch {
      #expect(error.localizedDescription.contains("100"))
    }

    let saveTodo = try #require(service.tools().first { $0.name == "things_save_todo" })
    do {
      _ = try await saveTodo([
        "titles": .array((0..<251).map { .string("Todo \($0)") })
      ])
      Issue.record("Expected bulk title limit validation")
    } catch {
      #expect(error.localizedDescription.contains("250"))
    }
    do {
      _ = try await saveTodo([
        "titles": .array([.string("One"), .string("Two")]),
        "show_quick_entry": .bool(true),
      ])
      Issue.record("Expected bulk creation to conflict with Quick Entry")
    } catch {
      #expect(error.localizedDescription.contains("cannot be used together"))
    }

    let batch = try #require(service.tools().first { $0.name == "things_batch" })
    let rows = (0..<101).map { index in
      Value.object([
        "type": .string("checklist-item"),
        "attributes": .object(["title": .string("Row \(index)")]),
      ])
    }
    do {
      _ = try await batch([
        "items": .array([
          .object([
            "type": .string("to-do"),
            "attributes": .object([
              "title": .string("Oversized"), "checklist-items": .array(rows),
            ]),
          ])
        ])
      ])
      Issue.record("Expected nested checklist limit validation")
    } catch {
      #expect(error.localizedDescription.contains("100"))
    }

    #expect(builder.jsonRequests.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("repeating and project state preconditions fail before URL dispatch")
  func writeStatePreconditions() async throws {
    let repository = ThingsRepositorySpy()
    repository.token = "token"
    var repeatingTodo = ThingsTestFixtures.todoWithChecklist
    repeatingTodo.repeating = ThingsTestFixtures.repeatingMetadata
    repository.todo = repeatingTodo
    var repeatingProject = ThingsTestFixtures.projectOne
    repeatingProject.repeating = ThingsTestFixtures.repeatingMetadata
    repository.projects = [repeatingProject]
    let callback = ThingsCallbackExecutorSpy()
    let service = makeThingsService(repository: repository, callback: callback)

    let saveTodo = try #require(service.tools().first { $0.name == "things_save_todo" })
    do {
      _ = try await saveTodo([
        "id": .string("todo:todo-1"), "deadline": .string("2026-08-01"),
      ])
      Issue.record("Expected repeating todo update to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("repeating todo"))
    }

    let saveProject = try #require(service.tools().first { $0.name == "things_save_project" })
    do {
      _ = try await saveProject([
        "id": .string("project:project-1"), "duplicate": .bool(true),
      ])
      Issue.record("Expected repeating project duplicate to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("repeating project"))
    }

    let projectWithIncompleteTodo = ThingsProject(
      id: "project:project-1",
      type: .project,
      title: "Launch",
      status: .incomplete,
      list: "anytime",
      when: nil,
      deadline: nil,
      completedAt: nil,
      notes: nil,
      area: nil,
      tags: [],
      createdAt: nil,
      updatedAt: nil,
      headings: [],
      todos: [ThingsReference(id: "todo:todo-1", title: "Prepare launch")],
      url: "things:///show?id=project-1"
    )
    repository.projects = [projectWithIncompleteTodo]
    repository.todo = ThingsTestFixtures.todoWithChecklist
    do {
      _ = try await saveProject([
        "id": .string("project:project-1"), "status": .string("completed"),
      ])
      Issue.record("Expected incomplete project children to block completion")
    } catch {
      #expect(error.localizedDescription.contains("child todos"))
    }

    let batch = try #require(service.tools().first { $0.name == "things_batch" })
    repository.todo = repeatingTodo
    do {
      _ = try await batch([
        "items": .array([
          .object([
            "type": .string("to-do"),
            "operation": .string("update"),
            "id": .string("todo:todo-1"),
            "attributes": .object(["when": .string("today")]),
          ])
        ])
      ])
      Issue.record("Expected JSON repeating update to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("repeating todo"))
    }
    #expect(callback.urls.isEmpty)
  }
}
