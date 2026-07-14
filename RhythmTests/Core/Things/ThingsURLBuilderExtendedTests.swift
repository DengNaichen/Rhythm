import Foundation
import Testing

@testable import Rhythm

@Suite("Things URL Scheme extensions")
@MainActor
struct ThingsURLBuilderExtendedTests {
  @Test("builds bulk add, clipboard, Quick Entry, timestamps, and callbacks")
  func todoAddExtensions() throws {
    var request = ThingsTodoSaveRequest()
    request.reveal = true
    let callbacks = ThingsURLCallbacks(
      success: URL(string: "rhythm://things/success?source=add")!,
      error: URL(string: "rhythm://things/error")!,
      cancel: URL(string: "rhythm://things/cancel")!
    )

    let url = try ThingsURLBuilder().saveTodoURL(
      for: request,
      authToken: nil,
      options: ThingsTodoURLCommandOptions(
        titles: ["Milk & bread", "芝士"],
        useClipboard: .replaceNotes,
        creationDate: "2026-07-13T10:00:00+08:00",
        completionDate: "2026-07-13T11:00:00Z",
        callbacks: callbacks
      )
    )

    #expect(
      url.absoluteString
        == "things:///add?titles=Milk%20%26%20bread%0A%E8%8A%9D%E5%A3%AB&use-clipboard=replace-notes&creation-date=2026-07-13T10%3A00%3A00%2B08%3A00&completion-date=2026-07-13T11%3A00%3A00Z&reveal=true&x-success=rhythm%3A%2F%2Fthings%2Fsuccess%3Fsource%3Dadd&x-error=rhythm%3A%2F%2Fthings%2Ferror&x-cancel=rhythm%3A%2F%2Fthings%2Fcancel"
    )

    var quickEntry = ThingsTodoSaveRequest()
    quickEntry.title = "Fallback"
    #expect(
      try ThingsURLBuilder().saveTodoURL(
        for: quickEntry,
        authToken: nil,
        options: ThingsTodoURLCommandOptions(
          useClipboard: .replaceNotes,
          showQuickEntry: true
        )
      ).absoluteString
        == "things:///add?title=Fallback&use-clipboard=replace-notes&show-quick-entry=true"
    )
  }

  @Test("builds duplicate updates and project initial to-dos")
  func duplicateAndProjectTodos() throws {
    var todo = ThingsTodoSaveRequest()
    todo.id = "todo:todo-123"
    let todoURL = try ThingsURLBuilder().saveTodoURL(
      for: todo,
      authToken: "secret",
      options: ThingsTodoURLCommandOptions(
        duplicate: true,
        creationDate: "2026-01-01T00:00:00Z",
        completionDate: "2026-01-02T00:00:00Z"
      )
    )
    #expect(
      todoURL.absoluteString
        == "things:///update?id=todo-123&auth-token=secret&duplicate=true&creation-date=2026-01-01T00%3A00%3A00Z&completion-date=2026-01-02T00%3A00%3A00Z"
    )

    var project = ThingsProjectSaveRequest()
    project.title = "Launch"
    let projectURL = try ThingsURLBuilder().saveProjectURL(
      for: project,
      authToken: nil,
      options: ThingsProjectURLCommandOptions(
        initialTodos: ["Design", "Build & ship"],
        creationDate: "2026-01-01T00:00:00Z"
      )
    )
    #expect(
      projectURL.absoluteString
        == "things:///add-project?title=Launch&to-dos=Design%0ABuild%20%26%20ship&creation-date=2026-01-01T00%3A00%3A00Z"
    )

    project.id = "project:project-123"
    project.title = nil
    let duplicateURL = try ThingsURLBuilder().saveProjectURL(
      for: project,
      authToken: "secret",
      options: ThingsProjectURLCommandOptions(duplicate: true)
    )
    #expect(
      duplicateURL.absoluteString
        == "things:///update-project?id=project-123&auth-token=secret&duplicate=true"
    )
  }

  @Test("rejects add-only and update-only URL fields in the wrong operation")
  func operationValidation() throws {
    var createTodo = ThingsTodoSaveRequest()
    createTodo.title = "Create"
    do {
      _ = try ThingsURLBuilder().saveTodoURL(
        for: createTodo,
        authToken: nil,
        options: ThingsTodoURLCommandOptions(duplicate: true)
      )
      Issue.record("Expected duplicate to require an update")
    } catch {
      #expect(error.localizedDescription.contains("duplicate"))
    }

    var updateTodo = ThingsTodoSaveRequest()
    updateTodo.id = "todo:todo-123"
    do {
      _ = try ThingsURLBuilder().saveTodoURL(
        for: updateTodo,
        authToken: "secret",
        options: ThingsTodoURLCommandOptions(titles: ["One", "Two"])
      )
      Issue.record("Expected titles to require an add")
    } catch {
      #expect(error.localizedDescription.contains("add-only"))
    }

    var updateProject = ThingsProjectSaveRequest()
    updateProject.id = "project:project-123"
    do {
      _ = try ThingsURLBuilder().saveProjectURL(
        for: updateProject,
        authToken: "secret",
        options: ThingsProjectURLCommandOptions(initialTodos: ["Child"])
      )
      Issue.record("Expected initial to-dos to require an add")
    } catch {
      #expect(error.localizedDescription.contains("initialTodos"))
    }

    let conflictingCases: [(ThingsTodoSaveRequest, ThingsTodoURLCommandOptions)] = [
      (
        {
          var request = ThingsTodoSaveRequest()
          request.title = "One"
          return request
        }(), ThingsTodoURLCommandOptions(titles: ["Two"])
      ),
      (ThingsTodoSaveRequest(), ThingsTodoURLCommandOptions(titles: ["One"], showQuickEntry: true)),
      (
        {
          var request = ThingsTodoSaveRequest()
          request.notes = .value("Explicit")
          return request
        }(), ThingsTodoURLCommandOptions(useClipboard: .replaceNotes)
      ),
      (
        {
          var request = ThingsTodoSaveRequest()
          request.reveal = true
          return request
        }(), ThingsTodoURLCommandOptions(showQuickEntry: true)
      ),
    ]
    for (request, options) in conflictingCases {
      do {
        _ = try ThingsURLBuilder().saveTodoURL(
          for: request,
          authToken: nil,
          options: options
        )
        Issue.record("Expected silently ignored fields to be rejected")
      } catch {
        #expect(error.localizedDescription.contains("cannot be used together"))
      }
    }
  }

  @Test("builds native show, search, and version URLs")
  func navigationCommands() throws {
    let builder = ThingsURLBuilder()
    #expect(try builder.searchURL().absoluteString == "things:///search")
    #expect(
      try builder.searchURL(query: "road map & launch").absoluteString
        == "things:///search?query=road%20map%20%26%20launch"
    )
    #expect(
      try builder.showURL(query: "Vacation in Rome", filterTags: ["Deep Work"]).absoluteString
        == "things:///show?query=Vacation%20in%20Rome&filter=Deep%20Work"
    )

    let success = try #require(URL(string: "rhythm://things/version"))
    #expect(
      try builder.versionURL(callbacks: ThingsURLCallbacks(success: success)).absoluteString
        == "things:///version?x-success=rhythm%3A%2F%2Fthings%2Fversion"
    )
  }

  @Test("encodes JSON projects, headings, checklist state, and updates")
  func jsonCommand() throws {
    let project = ThingsJSONItem.project(
      attributes: ThingsJSONProjectAttributes(
        title: "Launch 🚀",
        area: "Work",
        items: [
          .heading(ThingsJSONHeadingAttributes(title: "Planning", archived: false)),
          .todo(
            ThingsJSONTodoAttributes(
              title: "Research",
              checklistItems: [
                ThingsJSONChecklistItem(title: "Docs", completed: true),
                ThingsJSONChecklistItem(title: "API", canceled: true),
              ]
            )),
        ]
      )
    )
    let update = ThingsJSONItem.todo(
      operation: .update,
      id: "todo-123",
      attributes: ThingsJSONTodoAttributes(
        appendNotes: "Ship it",
        addTags: "Work,Urgent",
        prependChecklistItems: "QA\nReview"
      )
    )
    let success = try #require(URL(string: "rhythm://things/json-success"))
    let url = try ThingsURLBuilder().jsonURL(
      for: ThingsJSONCommandRequest(
        items: [project, update],
        authToken: "tok en&",
        reveal: true,
        callbacks: ThingsURLCallbacks(success: success)
      )
    )

    #expect(url.absoluteString.hasPrefix("things:///json?data=%5B"))
    let query = try Self.queryValues(url)
    #expect(query["auth-token"] == "tok en&")
    #expect(query["reveal"] == "true")
    #expect(query["x-success"] == "rhythm://things/json-success")

    let json = try #require(query["data"])
    let data = try #require(json.data(using: .utf8))
    let decoded = try JSONDecoder().decode([ThingsJSONItem].self, from: data)
    #expect(decoded == [project, update])

    let root = try #require(
      JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let projectObject = root[0]
    #expect(projectObject["type"] as? String == "project")
    let projectAttributes = try #require(projectObject["attributes"] as? [String: Any])
    let children = try #require(projectAttributes["items"] as? [[String: Any]])
    #expect(children[0]["type"] as? String == "heading")
    let todoAttributes = try #require(children[1]["attributes"] as? [String: Any])
    let checklist = try #require(todoAttributes["checklist-items"] as? [[String: Any]])
    #expect(checklist[0]["type"] as? String == "checklist-item")
    let checklistAttributes = try #require(checklist[0]["attributes"] as? [String: Any])
    #expect(checklistAttributes["completed"] as? Bool == true)

    #expect(root[1]["operation"] as? String == "update")
    #expect(root[1]["id"] as? String == "todo-123")
  }

  @Test("JSON data has no aggregate 4k cap but nested strings keep their limits")
  func jsonStringLimits() throws {
    let builder = ThingsURLBuilder()
    let longNotes = String(repeating: "n", count: 5_000)
    let validURL = try builder.jsonURL(
      for: ThingsJSONCommandRequest(
        items: [.todo(attributes: ThingsJSONTodoAttributes(title: "Long", notes: longNotes))]
      ))
    let data = try #require(Self.queryValues(validURL)["data"])
    #expect(data.count > 4_000)

    let invalidItems: [ThingsJSONItem] = [
      .todo(
        attributes: ThingsJSONTodoAttributes(title: String(repeating: "t", count: 4_001))),
      .todo(
        attributes: ThingsJSONTodoAttributes(notes: String(repeating: "n", count: 10_001))),
    ]
    for item in invalidItems {
      do {
        _ = try builder.jsonURL(for: ThingsJSONCommandRequest(items: [item]))
        Issue.record("Expected nested JSON string limit validation")
      } catch {
        #expect(error.localizedDescription.contains("maximum unencoded length"))
      }
    }
  }

  @Test("JSON updates require IDs and auth tokens")
  func jsonValidation() throws {
    let missingID = ThingsJSONCommandRequest(
      items: [
        .todo(operation: .update, attributes: ThingsJSONTodoAttributes(title: "Updated"))
      ],
      authToken: "secret"
    )
    do {
      _ = try ThingsURLBuilder().jsonURL(for: missingID)
      Issue.record("Expected an update ID")
    } catch {
      #expect(error.localizedDescription.contains("require an id"))
    }

    let missingToken = ThingsJSONCommandRequest(
      items: [
        .project(
          operation: .update,
          id: "project-123",
          attributes: ThingsJSONProjectAttributes(title: "Updated")
        )
      ]
    )
    do {
      _ = try ThingsURLBuilder().jsonURL(for: missingToken)
      Issue.record("Expected an auth token")
    } catch {
      #expect(error.localizedDescription.contains("auth token"))
    }
  }

  @Test("normalizes typed IDs in JSON attributes")
  func jsonTypedIDNormalization() throws {
    let request = ThingsJSONCommandRequest(
      items: [
        .todo(
          attributes: ThingsJSONTodoAttributes(
            title: "Todo",
            listID: "project:project-id",
            headingID: "heading:heading-id"
          )),
        .project(
          attributes: ThingsJSONProjectAttributes(
            title: "Project",
            areaID: "area:area-id"
          )),
      ]
    )
    let query = try Self.queryValues(ThingsURLBuilder().jsonURL(for: request))
    let json = try #require(query["data"])
    let data = try #require(json.data(using: .utf8))
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    let todo = try #require(root[0]["attributes"] as? [String: Any])
    #expect(todo["list-id"] as? String == "project-id")
    #expect(todo["heading-id"] as? String == "heading-id")
    let project = try #require(root[1]["attributes"] as? [String: Any])
    #expect(project["area-id"] as? String == "area-id")
  }

  private static func queryValues(_ url: URL) throws -> [String: String] {
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
  }
}
