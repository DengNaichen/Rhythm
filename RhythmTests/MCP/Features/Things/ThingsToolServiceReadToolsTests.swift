import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service read tools")
@MainActor
struct ThingsToolServiceReadToolsTests {
  @Test("maps list_todos filters and opaque cursor pagination")
  func listTodosMapping() async throws {
    let repository = ThingsRepositorySpy()
    repository.todoPage = ThingsPage(
      items: [ThingsTestFixtures.sampleTodo],
      nextCursor: "42"
    )
    let service = ThingsToolService(
      urlBuilder: ThingsURLBuilderSpy(),
      callbackExecutor: ThingsCallbackExecutorSpy(),
      repository: repository
    )
    let tool = try #require(service.tools().first { $0.name == "things_list_todos" })

    let result = try await tool([
      "list": .string("logbook"),
      "query": .string(" launch "),
      "project": .string("project:project-id"),
      "area": .string("area:area-id"),
      "heading": .string("heading-id"),
      "tag": .string("Deep Work"),
      "scheduled_on": .string("2026-07-13"),
      "deadline_from": .string("2026-08-01"),
      "deadline_to": .string("2026-08-31"),
      "order_by": .string("deadline"),
      "order_direction": .string("desc"),
      "cursor": .string("25"),
      "limit": .int(17),
    ])

    let query = try #require(repository.lastTodoQuery)
    #expect(query.list == .logbook)
    #expect(query.query == "launch")
    #expect(query.status == .all)
    #expect(query.project == "project:project-id")
    #expect(query.area == "area:area-id")
    #expect(query.heading == "heading-id")
    #expect(query.tag == "Deep Work")
    #expect(query.scheduledOn == "2026-07-13")
    #expect(query.scheduledFrom == nil)
    #expect(query.scheduledTo == nil)
    #expect(query.deadlineOn == nil)
    #expect(query.deadlineFrom == "2026-08-01")
    #expect(query.deadlineTo == "2026-08-31")
    #expect(query.orderBy == .deadline)
    #expect(query.orderDirection == .descending)
    #expect(query.page == ThingsPageRequest(offset: 25, limit: 17))

    let object = try #require(result.objectValue)
    #expect(object["count"] == .int(1))
    #expect(object["next_cursor"] == .string("42"))
    #expect(object["has_more"] == .bool(true))
  }

  @Test("rejects conflicting and reversed Things date filters")
  func dateFilterValidation() async throws {
    let repository = ThingsRepositorySpy()
    let service = ThingsToolService(
      urlBuilder: ThingsURLBuilderSpy(),
      callbackExecutor: ThingsCallbackExecutorSpy(),
      repository: repository
    )
    let todos = try #require(service.tools().first { $0.name == "things_list_todos" })

    let invalidTodoArguments: [[String: Value]] = [
      [
        "scheduled_on": .string("2026-07-13"),
        "scheduled_from": .string("2026-07-01"),
      ],
      [
        "created_from": .string("2026-07-14T00:00:00Z"),
        "created_to": .string("2026-07-13T23:59:59Z"),
      ],
    ]
    for arguments in invalidTodoArguments {
      var caught = false
      do {
        _ = try await todos(arguments)
      } catch {
        caught = true
        #expect(
          error.localizedDescription.contains("cannot be used together")
            || error.localizedDescription.contains("lower bound")
        )
      }
      #expect(caught)
    }
    #expect(repository.lastTodoQuery == nil)

    _ = try await todos([
      "reminder_from": .string("2026-07-13T10:00:00Z"),
      "reminder_to": .string("2026-07-13T20:00:00+00:00"),
      "created_from": .string("2026-07-13T10:00:00Z"),
      "created_to": .string("2026-07-13T20:00:00+00:00"),
    ])
    #expect(repository.lastTodoQuery?.createdFrom == "2026-07-13T10:00:00Z")

    repository.lastProjectQuery = nil
    let projects = try #require(service.tools().first { $0.name == "things_list_projects" })
    var caughtProjectRange = false
    do {
      _ = try await projects([
        "deadline_from": .string("2026-08-02"),
        "deadline_to": .string("2026-08-01"),
      ])
    } catch {
      caughtProjectRange = true
      #expect(error.localizedDescription.contains("lower bound"))
    }
    #expect(caughtProjectRange)
    #expect(repository.lastProjectQuery == nil)
  }

  @Test("defaults Logbook project reads to all statuses")
  func logbookProjectStatusDefault() async throws {
    let repository = ThingsRepositorySpy()
    let service = ThingsToolService(
      urlBuilder: ThingsURLBuilderSpy(),
      callbackExecutor: ThingsCallbackExecutorSpy(),
      repository: repository
    )
    let tool = try #require(service.tools().first { $0.name == "things_list_projects" })

    _ = try await tool(["when": .string("logbook")])

    let query = try #require(repository.lastProjectQuery)
    #expect(query.when == .logbook)
    #expect(query.status == .all)
  }

  @Test("heading list and get arguments map to repository queries")
  func headingReadMapping() async throws {
    let repository = ThingsRepositorySpy()
    repository.headingPage = ThingsPage(items: [ThingsTestFixtures.heading], nextCursor: "30")
    repository.heading = ThingsTestFixtures.heading
    let service = makeThingsService(repository: repository)

    let list = try #require(service.tools().first { $0.name == "things_list_headings" })
    let listResult = try await list([
      "query": .string("  Phase  "),
      "status": .string("completed"),
      "project": .string("project:project-1"),
      "is_logged": .bool(true),
      "include_todos": .bool(true),
      "order_by": .string("title"),
      "order_direction": .string("desc"),
      "cursor": .string("10"),
      "limit": .int(20),
    ])

    let query = try #require(repository.lastHeadingQuery)
    #expect(query.query == "Phase")
    #expect(query.status == .completed)
    #expect(query.project == "project:project-1")
    #expect(query.isLogged == true)
    #expect(query.includeTodos)
    #expect(query.orderBy == .title)
    #expect(query.orderDirection == .descending)
    #expect(query.page == ThingsPageRequest(offset: 10, limit: 20))
    #expect(listResult.objectValue?["next_cursor"] == .string("30"))

    let get = try #require(service.tools().first { $0.name == "things_get_heading" })
    let getResult = try await get([
      "id": .string("  heading:heading-1  "),
      "include_todos": .bool(true),
    ])
    #expect(repository.lastHeadingLookup == "heading:heading-1")
    #expect(repository.lastHeadingIncludeTodos == true)
    #expect(getResult.objectValue?["id"] == .string("heading:heading-1"))
  }
}
