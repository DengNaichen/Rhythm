import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service lifecycle tools")
@MainActor
struct ThingsToolServiceLifecycleToolsTests {
  @Test("delete, restore, empty trash, and log completed use automation safely")
  func managementMappingAndValidation() async throws {
    let repository = ThingsRepositorySpy()
    repository.fetchedEntities["todo:todo-1"] = .todo(ThingsTestFixtures.todoWithChecklist)
    repository.fetchedEntities[ThingsTestFixtures.projectOne.id] = .project(
      ThingsTestFixtures.projectOne)
    repository.fetchedEntities["area:area-1"] = .area(ThingsTestFixtures.area)
    repository.fetchedEntities["tag:existing"] = .tag(ThingsTestFixtures.existingTag)
    var parentWithChildren = ThingsTestFixtures.parentTag
    parentWithChildren.children = [ThingsReference(id: "tag:child", title: "Child")]
    repository.fetchedEntities["tag:parent"] = .tag(parentWithChildren)
    let automation = ThingsAutomationExecutorSpy()
    let service = makeThingsService(repository: repository, automation: automation)

    let delete = try #require(service.tools().first { $0.name == "things_delete" })
    var caughtCascade = false
    do {
      _ = try await delete(["ref": .string("area:area-1")])
    } catch {
      caughtCascade = true
      #expect(error.localizedDescription.contains("confirm_cascade"))
    }
    #expect(caughtCascade)
    #expect(await automation.commands.isEmpty)

    _ = try await delete([
      "ref": .string("area:area-1"),
      "confirm_cascade": .bool(true),
    ])

    do {
      _ = try await delete(["ref": .string("tag:existing")])
      Issue.record("Expected permanent tag deletion to require confirmation")
    } catch {
      #expect(error.localizedDescription.contains("confirm_permanent"))
    }
    _ = try await delete([
      "ref": .string("tag:existing"),
      "confirm_permanent": .bool(true),
    ])

    do {
      _ = try await delete([
        "ref": .string("tag:parent"),
        "confirm_permanent": .bool(true),
      ])
      Issue.record("Expected parent tag deletion to require cascade confirmation")
    } catch {
      #expect(error.localizedDescription.contains("confirm_cascade"))
    }
    _ = try await delete([
      "ref": .string("tag:parent"),
      "confirm_permanent": .bool(true),
      "confirm_cascade": .bool(true),
    ])

    let restore = try #require(service.tools().first { $0.name == "things_restore" })
    do {
      _ = try await restore([
        "ref": .string("todo:todo-1"),
        "destination": .string("project-1"),
      ])
      Issue.record("Expected an untyped restore destination to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("typed"))
    }
    _ = try await restore(["ref": .string("todo:todo-1")])

    let emptyTrash = try #require(service.tools().first { $0.name == "things_empty_trash" })
    var caughtConfirmation = false
    do {
      _ = try await emptyTrash(["confirm": .bool(false)])
    } catch {
      caughtConfirmation = true
      #expect(error.localizedDescription.contains("must be true"))
    }
    #expect(caughtConfirmation)

    _ = try await emptyTrash(["confirm": .bool(true)])
    let log = try #require(service.tools().first { $0.name == "things_log_completed" })
    _ = try await log([:])

    let commands = await automation.commands
    #expect(commands.count == 6)
    #expect(commands[0] == .trash(kind: .area, id: "area-1"))
    #expect(commands[1] == .trash(kind: .tag, id: "existing"))
    #expect(commands[2] == .trash(kind: .tag, id: "parent"))
    #expect(
      commands[3]
        == .restore(
          kind: .todo,
          id: "todo-1",
          destinations: [.project("project:project-1"), .builtin("Inbox")]
        )
    )
    #expect(commands[4] == .emptyTrash)
    #expect(commands[5] == .logCompleted)
  }

  @Test("restore never targets a project that is still in Trash")
  func restoreRejectsTrashedProjectDestination() async throws {
    let repository = ThingsRepositorySpy()
    repository.fetchedEntities[ThingsTestFixtures.todoInTrashedProject.id] = .todo(
      ThingsTestFixtures.todoInTrashedProject)
    repository.fetchedEntities[ThingsTestFixtures.projectInTrash.id] = .project(
      ThingsTestFixtures.projectInTrash)
    let automation = ThingsAutomationExecutorSpy()
    let service = makeThingsService(repository: repository, automation: automation)
    let restore = try #require(service.tools().first { $0.name == "things_restore" })

    _ = try await restore(["ref": .string(ThingsTestFixtures.todoInTrashedProject.id)])
    #expect(
      await automation.commands
        == [
          .restore(
            kind: .todo,
            id: "todo-in-trash",
            destinations: [.builtin("Inbox")]
          )
        ])

    do {
      _ = try await restore([
        "ref": .string(ThingsTestFixtures.todoInTrashedProject.id),
        "destination": .string(ThingsTestFixtures.projectInTrash.id),
      ])
      Issue.record("Expected a trashed destination project to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("destination project is in Trash"))
    }
    #expect(await automation.commands.count == 1)
  }
}
