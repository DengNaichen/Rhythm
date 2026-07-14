import Foundation

@testable import Rhythm

@MainActor
final class ThingsRepositorySpy: ThingsRepository {
  var lastTodoQuery: ThingsTodoQuery?
  var lastProjectQuery: ThingsProjectQuery?
  var lastHeadingQuery: ThingsHeadingQuery?
  var lastHeadingLookup: String?
  var lastHeadingIncludeTodos: Bool?

  var todoPage = ThingsPage<ThingsTodo>(items: [], nextCursor: nil)
  var projectPage = ThingsPage<ThingsProject>(items: [], nextCursor: nil)
  var headingPage = ThingsPage<ThingsHeading>(items: [], nextCursor: nil)
  var todo: ThingsTodo? = ThingsTestFixtures.defaultTodo
  var heading: ThingsHeading? = ThingsTestFixtures.defaultHeading
  var projects: [ThingsProject] = [ThingsTestFixtures.defaultProject]
  var areas: [ThingsArea] = [ThingsTestFixtures.defaultArea]
  var tags: [ThingsTag] = []
  var availableTags = ["Work", "Urgent", "Deep Work", "Home", "A", "B"]
  var fetchedEntities: [String: ThingsEntity] = [:]
  var resolvedShowTarget: ThingsReference?

  var token: String?
  var authTokenCallCount = 0

  func search(_ query: ThingsSearchQuery) throws -> ThingsPage<ThingsSearchHit> {
    ThingsPage(items: [], nextCursor: nil)
  }

  func fetch(_ reference: String, includeItems: Bool) throws -> ThingsEntity {
    guard let entity = fetchedEntities[reference] else {
      throw ThingsServiceError.entityNotFound(reference)
    }
    return entity
  }

  func listTodos(_ query: ThingsTodoQuery) throws -> ThingsPage<ThingsTodo> {
    lastTodoQuery = query
    return todoPage
  }

  func getTodo(id: String) throws -> ThingsTodo {
    guard let todo,
      todo.id == id
        || ThingsEntityID.parse(todo.id).rawID == ThingsEntityID.parse(id).rawID
    else {
      throw ThingsServiceError.entityNotFound(id)
    }
    return todo
  }

  func listHeadings(_ query: ThingsHeadingQuery) throws -> ThingsPage<ThingsHeading> {
    lastHeadingQuery = query
    return headingPage
  }

  func getHeading(idOrTitle: String, includeTodos: Bool) throws -> ThingsHeading {
    lastHeadingLookup = idOrTitle
    lastHeadingIncludeTodos = includeTodos
    guard let heading,
      heading.id == idOrTitle
        || heading.title.compare(
          idOrTitle,
          options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    else {
      throw ThingsServiceError.entityNotFound(idOrTitle)
    }
    return heading
  }

  func listProjects(_ query: ThingsProjectQuery) throws -> ThingsPage<ThingsProject> {
    lastProjectQuery = query
    return projectPage
  }

  func getProject(idOrTitle: String, includeTodos: Bool) throws -> ThingsProject {
    let matches = projects.filter {
      $0.id == idOrTitle
        || $0.title.compare(
          idOrTitle,
          options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
    guard let project = matches.first else {
      throw ThingsServiceError.entityNotFound(idOrTitle)
    }
    guard matches.count == 1 else {
      throw ThingsServiceError.ambiguousReference(idOrTitle)
    }
    return project
  }

  func listAreas(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsArea> {
    let items = areas.filter { area in
      guard let query = query.query else { return true }
      return area.title.localizedCaseInsensitiveContains(query)
    }
    return ThingsPage(items: items, nextCursor: nil)
  }

  func listTags(_ query: ThingsDirectoryQuery) throws -> ThingsPage<ThingsTag> {
    let source =
      tags.isEmpty
      ? availableTags.map { title in
        ThingsTag(
          id: "tag:\(title.replacingOccurrences(of: " ", with: "-"))",
          type: .tag,
          title: title,
          shortcut: nil,
          todoCount: 0,
          projectCount: 0,
          todos: nil,
          projects: nil,
          url: "things:///show?id=\(title)"
        )
      }
      : tags
    let items = source.filter { tag in
      guard let query = query.query else { return true }
      return tag.title.localizedCaseInsensitiveContains(query)
    }
    return ThingsPage(items: items, nextCursor: nil)
  }

  func resolveShowTarget(_ target: String) throws -> ThingsReference {
    guard let resolvedShowTarget else {
      throw ThingsServiceError.entityNotFound(target)
    }
    return resolvedShowTarget
  }

  func authToken() throws -> String? {
    authTokenCallCount += 1
    return token
  }
}
