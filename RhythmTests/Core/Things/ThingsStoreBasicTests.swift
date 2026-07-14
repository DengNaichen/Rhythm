import Foundation
import Testing

@testable import Rhythm

@Suite("Things store basic reads")
@MainActor
struct ThingsStoreBasicTests {
  @Test("SQLite store lists, gets, and searches quoted titles with bound parameters")
  func sqliteReadOperationsAndQuotedTitles() throws {
    let fixture = try SQLiteThingsFixture()
    defer { fixture.remove() }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let store = ThingsStore(
      databaseAccess: fixture,
      calendar: calendar,
      now: { Date(timeIntervalSince1970: 1_752_364_800) }
    )

    var listQuery = ThingsTodoQuery()
    listQuery.query = "O'Brien"
    listQuery.status = .all
    listQuery.page = ThingsPageRequest(offset: 0, limit: 1)
    let firstPage = try store.listTodos(listQuery)
    #expect(firstPage.items.map(\.title) == ["O'Brien's plan"])
    #expect(firstPage.nextCursor == "1")
    #expect(firstPage.hasMore)

    listQuery.page = ThingsPageRequest(offset: 1, limit: 1)
    let secondPage = try store.listTodos(listQuery)
    #expect(secondPage.items.map(\.title) == ["Archived O'Brien task"])
    #expect(secondPage.nextCursor == nil)

    let todo = try store.getTodo(id: "todo:todo-12345678901234567890")
    #expect(todo.title == "O'Brien's plan")
    #expect(todo.project?.title == "Client's Launch")
    #expect(todo.area?.title == "Team's Area")
    #expect(todo.heading?.id == "heading:heading-12345678901234567890")
    #expect(todo.tags == ["Deep Work"])
    #expect(
      todo.checklistItems == [
        ThingsChecklistItem(
          title: "Review PR",
          status: .incomplete,
          id: "checklist-12345678901234567890",
          index: 1
        )
      ])

    let project = try store.getProject(idOrTitle: "Client's Launch", includeTodos: true)
    #expect(project.id == "project:project-12345678901234567890")
    #expect(project.area?.title == "Team's Area")
    #expect(project.headings.map(\.title) == ["Launch's Phase"])
    #expect(project.todos?.count == 2)
    #expect(
      try store.resolveShowTarget("Team's Area").id
        == "area:area-12345678901234567890"
    )
    #expect(
      try store.resolveShowTarget("Deep Work").id
        == "tag:tag-12345678901234567890"
    )
    #expect(
      try store.resolveShowTarget("todo-12345678901234567890").id
        == "todo:todo-12345678901234567890"
    )
    #expect(
      try store.resolveShowTarget("heading-12345678901234567890").id
        == "heading:heading-12345678901234567890"
    )

    let incompleteSearch = try store.search(
      ThingsSearchQuery(
        query: "O'Brien",
        type: .todo,
        includeCompleted: false,
        includeCanceled: false,
        page: ThingsPageRequest(limit: 10)
      )
    )
    #expect(incompleteSearch.items.map(\.title) == ["O'Brien's plan"])

    let allSearch = try store.search(
      ThingsSearchQuery(
        query: "O'Brien",
        type: .todo,
        includeCompleted: true,
        includeCanceled: false,
        page: ThingsPageRequest(limit: 10)
      )
    )
    #expect(allSearch.items.map(\.title) == ["O'Brien's plan", "Archived O'Brien task"])
    #expect(try store.authToken() == "fixture-token")
  }
}
