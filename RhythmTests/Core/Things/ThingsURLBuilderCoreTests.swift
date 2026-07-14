import Foundation
import Testing

@testable import Rhythm

@Suite("Things URL builder core commands")
@MainActor
struct ThingsURLBuilderCoreTests {
  @Test("ThingsURLBuilder emits exact create and update URLs")
  func exactThingsURLs() throws {
    let builder = ThingsURLBuilder()

    var create = ThingsTodoSaveRequest()
    create.title = "Milk & bread"
    create.notes = .clear
    create.tags = .value(["Home", "Errands"])
    create.checklistItems = .value(["One", "Two"])
    create.destination = .value("project:project-123")
    create.heading = .value("Planning")
    create.status = .completed
    create.reveal = true

    let createURL = try builder.saveTodoURL(for: create, authToken: nil)
    #expect(
      createURL.absoluteString
        == "things:///add?title=Milk%20%26%20bread&notes=&tags=Home%2CErrands&checklist-items=One%0ATwo&list-id=project-123&heading=Planning&completed=true&reveal=true"
    )

    var update = ThingsTodoSaveRequest()
    update.id = "todo:todo-123"
    update.deadline = .clear
    update.addTags = ["A", "B"]
    update.destination = .value("area:area-123")
    update.status = .incomplete

    let updateURL = try builder.saveTodoURL(for: update, authToken: "tok en&")
    #expect(
      updateURL.absoluteString
        == "things:///update?id=todo-123&auth-token=tok%20en%26&deadline=&add-tags=A%2CB&list-id=area-123&completed=false&canceled=false"
    )

    var project = ThingsProjectSaveRequest()
    project.id = "project:project-123"
    project.notes = .value("A/B?")
    project.area = .clear
    project.status = .canceled

    let projectURL = try builder.saveProjectURL(for: project, authToken: "token")
    #expect(
      projectURL.absoluteString
        == "things:///update-project?id=project-123&auth-token=token&notes=A%2FB%3F&area=&canceled=true"
    )

    let showURL = try builder.showURL(
      id: "todo:todo-123",
      filterTags: ["Deep Work", "Home"]
    )
    #expect(
      showURL.absoluteString
        == "things:///show?id=todo-123&filter=Deep%20Work%2CHome"
    )
  }
}
