import Foundation
import Testing

@testable import Rhythm

@Suite("Things store advanced reads")
@MainActor
struct ThingsStoreAdvancedTests {
  @Test("SQLite store exposes advanced Things read semantics")
  func sqliteAdvancedReadOperations() throws {
    let fixture = try SQLiteThingsFixture()
    defer { fixture.remove() }

    let calendar = Calendar.current
    let store = ThingsStore(databaseAccess: fixture, calendar: calendar)
    func localTimestamp(_ epoch: TimeInterval, format: String) -> String {
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    func rfc3339(_ epoch: TimeInterval) -> String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    let todo = try store.getTodo(id: "todo:todo-32345678901234567890")
    #expect(todo.evening)
    #expect(todo.reminderTime == "18:45")
    #expect(todo.reminderAt == "2026-07-13T18:45")
    #expect(todo.tags.isEmpty)
    #expect(todo.allMatchingTags == ["Work", "Deep Focus"])
    #expect(
      todo.checklistItems.map(\.id) == [
        "checklist-22345678901234567890", "checklist-32345678901234567890",
      ])
    #expect(todo.checklistItems.map(\.index) == [1, 2])
    #expect(
      todo.checklistItems.first?.createdAt
        == localTimestamp(1_783_936_800, format: "yyyy-MM-dd HH:mm:ss"))
    #expect(
      todo.checklistItems.first?.updatedAt
        == localTimestamp(1_784_026_800, format: "yyyy-MM-dd HH:mm:ss"))

    let checklistSearch = try store.search(
      ThingsSearchQuery(
        query: "Hidden needle",
        type: .todo,
        includeCompleted: false,
        includeCanceled: false,
        page: ThingsPageRequest(limit: 10)
      ))
    #expect(checklistSearch.items.map(\.id) == ["todo-32345678901234567890"])

    var inheritedTodoQuery = ThingsTodoQuery()
    inheritedTodoQuery.query = "Inherited context"
    inheritedTodoQuery.tag = "Deep Focus"
    #expect(try store.listTodos(inheritedTodoQuery).items.count == 1)
    inheritedTodoQuery.includeInheritedTags = false
    #expect(try store.listTodos(inheritedTodoQuery).items.isEmpty)
    inheritedTodoQuery.tag = "Work"
    inheritedTodoQuery.includeInheritedTags = true
    #expect(try store.listTodos(inheritedTodoQuery).items.count == 1)
    inheritedTodoQuery.includeInheritedTags = false
    #expect(try store.listTodos(inheritedTodoQuery).items.isEmpty)

    var inheritedProjectQuery = ThingsProjectQuery()
    inheritedProjectQuery.query = "Advanced Reads"
    inheritedProjectQuery.tag = "Deep Focus"
    #expect(try store.listProjects(inheritedProjectQuery).items.count == 1)
    inheritedProjectQuery.includeInheritedTags = false
    #expect(try store.listProjects(inheritedProjectQuery).items.isEmpty)

    var directNestedTodoQuery = ThingsTodoQuery()
    directNestedTodoQuery.query = "Dated completion"
    directNestedTodoQuery.status = .completed
    directNestedTodoQuery.tag = "Work"
    directNestedTodoQuery.includeInheritedTags = false
    #expect(try store.listTodos(directNestedTodoQuery).items.count == 1)

    var directNestedProjectQuery = ThingsProjectQuery()
    directNestedProjectQuery.query = "Dated project"
    directNestedProjectQuery.status = .completed
    directNestedProjectQuery.tag = "Work"
    directNestedProjectQuery.includeInheritedTags = false
    #expect(try store.listProjects(directNestedProjectQuery).items.count == 1)
    inheritedProjectQuery.tag = "Work"
    inheritedProjectQuery.includeInheritedTags = true
    let parentTagProjects = try store.listProjects(inheritedProjectQuery).items
    #expect(parentTagProjects.count == 1)
    #expect(parentTagProjects.first?.allMatchingTags == ["Work", "Deep Focus"])
    inheritedProjectQuery.includeInheritedTags = false
    #expect(try store.listProjects(inheritedProjectQuery).items.isEmpty)

    guard
      case .area(let area) = try store.fetch(
        "area:area-22345678901234567890", includeItems: false)
    else {
      Issue.record("Expected an area")
      return
    }
    #expect(area.tags == ["Deep Focus"])
    #expect(area.allMatchingTags == ["Deep Focus"])

    guard
      case .tag(let childTag) = try store.fetch(
        "tag:tag-child-12345678901234567890", includeItems: false)
    else {
      Issue.record("Expected a tag")
      return
    }
    #expect(childTag.parent?.title == "Work")
    #expect(childTag.path.map(\.title) == ["Work", "Deep Focus"])

    guard
      case .tag(let parentTag) = try store.fetch(
        "tag:tag-parent-12345678901234567890", includeItems: true)
    else {
      Issue.record("Expected the parent tag")
      return
    }
    #expect(parentTag.children.map(\.title) == ["Deep Focus"])
    #expect(parentTag.todoCount == 4)
    #expect(parentTag.projectCount == 2)
    #expect(
      parentTag.todos?.map(\.id) == [
        "todo:todo-32345678901234567890",
        "todo:todo-repeat-12345678901234567890",
        "todo:todo-instance-12345678901234567890",
        "todo:todo-dated-12345678901234567890",
      ])
    #expect(
      parentTag.projects?.map(\.id) == [
        "project:project-32345678901234567890",
        "project:project-dated-12345678901234567890",
      ])
    guard
      case .tag(let parentTag) = try store.fetch(
        "tag:tag-parent-12345678901234567890", includeItems: false)
    else {
      Issue.record("Expected a parent tag")
      return
    }
    #expect(parentTag.children.map(\.title) == ["Deep Focus"])

    var repeatingQuery = ThingsTodoQuery()
    repeatingQuery.list = .repeating
    repeatingQuery.query = "Weekly review template"
    let repeating = try #require(store.listTodos(repeatingQuery).items.first)
    #expect(repeating.when == "2026-07-20")
    #expect(repeating.repeating?.isTemplate == true)
    #expect(repeating.repeating?.paused == true)
    #expect(repeating.repeating?.instanceCreationStart == "2026-07-13")
    #expect(repeating.repeating?.instanceCount == 4)
    #expect(
      repeating.repeating?.afterCompletionReferenceAt
        == localTimestamp(1_784_116_800, format: "yyyy-MM-dd HH:mm:ss"))
    #expect(repeating.repeating?.deadlineOffsetDays == -2)
    #expect(repeating.repeating?.ruleDataBase64 == "AQIDBA==")

    let instance = try store.getTodo(id: "todo:todo-instance-12345678901234567890")
    #expect(instance.repeating?.isTemplate == false)
    #expect(instance.repeating?.template?.id == "todo:todo-repeat-12345678901234567890")

    let loggedTodo = try store.getTodo(id: "todo:todo-logged-12345678901234567890")
    #expect(loggedTodo.status == .incomplete)
    #expect(loggedTodo.isLogged)
    var logbookQuery = ThingsTodoQuery()
    logbookQuery.list = .logbook
    logbookQuery.status = .all
    logbookQuery.query = "Reopened logged child"
    #expect(try store.listTodos(logbookQuery).items.count == 1)
    logbookQuery.list = .anytime
    logbookQuery.status = .incomplete
    #expect(try store.listTodos(logbookQuery).items.isEmpty)

    var headingQuery = ThingsHeadingQuery()
    headingQuery.project = "project:project-logged-12345678901234567890"
    headingQuery.includeTodos = true
    let heading = try #require(store.listHeadings(headingQuery).items.first)
    #expect(heading.id == "heading:heading-logged-12345678901234567890")
    #expect(heading.isLogged)
    #expect(heading.todos?.map(\.id) == ["todo:todo-logged-12345678901234567890"])
    guard
      case .heading(let fetchedHeading) = try store.fetch(heading.id, includeItems: true)
    else {
      Issue.record("Expected a heading")
      return
    }
    #expect(fetchedHeading.project.title == "Logged parent project")

    var todoDateQuery = ThingsTodoQuery()
    todoDateQuery.query = "Dated completion"
    todoDateQuery.status = .all
    todoDateQuery.createdFrom = localTimestamp(1_783_936_800, format: "yyyy-MM-dd")
    todoDateQuery.createdTo = localTimestamp(1_783_936_800, format: "yyyy-MM-dd")
    todoDateQuery.updatedFrom = localTimestamp(1_784_026_800, format: "yyyy-MM-dd'T'HH:mm")
    todoDateQuery.updatedTo = localTimestamp(1_784_026_800, format: "yyyy-MM-dd'T'HH:mm")
    todoDateQuery.completedFrom = localTimestamp(
      1_784_116_800, format: "yyyy-MM-dd'T'HH:mm:ss")
    todoDateQuery.completedTo = localTimestamp(
      1_784_116_800, format: "yyyy-MM-dd'T'HH:mm:ss")
    #expect(try store.listTodos(todoDateQuery).items.map(\.title) == ["Dated completion"])

    todoDateQuery.createdFrom = rfc3339(1_783_936_800)
    todoDateQuery.createdTo = rfc3339(1_783_936_800)
    todoDateQuery.updatedFrom = rfc3339(1_784_026_800)
    todoDateQuery.updatedTo = rfc3339(1_784_026_800)
    todoDateQuery.completedFrom = rfc3339(1_784_116_800)
    todoDateQuery.completedTo = rfc3339(1_784_116_800)
    #expect(try store.listTodos(todoDateQuery).items.map(\.title) == ["Dated completion"])

    let reminderDate = try #require(
      calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 13, hour: 18, minute: 45)))
    var reminderQuery = ThingsTodoQuery()
    reminderQuery.query = "Inherited context"
    reminderQuery.reminderFrom = rfc3339(reminderDate.timeIntervalSince1970)
    reminderQuery.reminderTo = rfc3339(reminderDate.timeIntervalSince1970)
    #expect(try store.listTodos(reminderQuery).items.map(\.title) == ["Inherited context"])

    var projectDateQuery = ThingsProjectQuery()
    projectDateQuery.query = "Dated project"
    projectDateQuery.status = .all
    projectDateQuery.createdFrom = localTimestamp(1_783_936_800, format: "yyyy-MM-dd")
    projectDateQuery.createdTo = localTimestamp(1_783_936_800, format: "yyyy-MM-dd")
    projectDateQuery.updatedFrom = localTimestamp(
      1_784_026_800, format: "yyyy-MM-dd'T'HH:mm")
    projectDateQuery.updatedTo = localTimestamp(
      1_784_026_800, format: "yyyy-MM-dd'T'HH:mm")
    projectDateQuery.completedFrom = localTimestamp(1_784_116_800, format: "yyyy-MM-dd")
    projectDateQuery.completedTo = localTimestamp(1_784_116_800, format: "yyyy-MM-dd")
    #expect(try store.listProjects(projectDateQuery).items.map(\.title) == ["Dated project"])

    projectDateQuery.createdFrom = rfc3339(1_783_936_800)
    projectDateQuery.createdTo = rfc3339(1_783_936_800)
    projectDateQuery.updatedFrom = rfc3339(1_784_026_800)
    projectDateQuery.updatedTo = rfc3339(1_784_026_800)
    projectDateQuery.completedFrom = rfc3339(1_784_116_800)
    projectDateQuery.completedTo = rfc3339(1_784_116_800)
    #expect(try store.listProjects(projectDateQuery).items.map(\.title) == ["Dated project"])

    var defaultTrashSearch = ThingsSearchQuery(
      query: "Trash needle",
      type: .todo,
      includeCompleted: false,
      includeCanceled: false,
      page: ThingsPageRequest(limit: 10)
    )
    #expect(try store.search(defaultTrashSearch).items.isEmpty)
    defaultTrashSearch.includeTrashed = true
    #expect(try store.search(defaultTrashSearch).items.map(\.title) == ["Trash needle"])

    var headingTrashSearch = ThingsSearchQuery(
      query: "Trashed heading needle",
      type: .heading,
      includeCompleted: false,
      includeCanceled: false,
      page: ThingsPageRequest(limit: 10)
    )
    #expect(try store.search(headingTrashSearch).items.isEmpty)
    headingTrashSearch.includeTrashed = true
    #expect(
      try store.search(headingTrashSearch).items.map(\.title) == ["Trashed heading needle"])

    for (title, id) in [
      ("Heading inherited deletion", "todo-heading-trash-12345678901234567890"),
      ("Project inherited deletion", "todo-project-trash-12345678901234567890"),
    ] {
      var ordinaryQuery = ThingsTodoQuery()
      ordinaryQuery.query = title
      #expect(try store.listTodos(ordinaryQuery).items.isEmpty)

      var trashQuery = ordinaryQuery
      trashQuery.list = .trash
      let inheritedTrash = try #require(store.listTodos(trashQuery).items.first)
      #expect(inheritedTrash.id == "todo:\(id)")
      #expect(inheritedTrash.list == "trash")
      #expect(try store.getTodo(id: "todo:\(id)").list == "trash")

      var searchQuery = ThingsSearchQuery(
        query: title,
        type: .todo,
        includeCompleted: false,
        includeCanceled: false,
        page: ThingsPageRequest(limit: 10)
      )
      #expect(try store.search(searchQuery).items.isEmpty)
      searchQuery.includeTrashed = true
      #expect(try store.search(searchQuery).items.map(\.id) == [id])
    }
  }
}
