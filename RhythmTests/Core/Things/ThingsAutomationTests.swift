import Foundation
import Testing

@testable import Rhythm

@Suite("Things Automation")
struct ThingsAutomationTests {
  @Test("builds safe area and tag AppleScripts")
  func saveDirectoryScripts() throws {
    let builder = ThingsAppleScriptBuilder()

    var area = ThingsAreaAutomationRequest()
    area.title = "Client \"Launch\""
    area.tags = .value(["Work", "Deep Work"])
    area.collapsed = true
    let areaScript = try builder.script(for: .saveArea(area))
    #expect(areaScript.contains("make new area"))
    #expect(areaScript.contains("Client \\\"Launch\\\""))
    #expect(areaScript.contains("set tag names of targetArea to \"Work, Deep Work\""))
    #expect(areaScript.contains("set collapsed of targetArea to true"))
    #expect(areaScript.contains("return id of targetArea"))

    var tag = ThingsTagAutomationRequest()
    tag.id = "tag:child-12345678901234567890"
    tag.title = "Focus"
    tag.shortcut = .clear
    tag.parent = .value("tag:parent-12345678901234567890")
    let tagScript = try builder.script(for: .saveTag(tag))
    #expect(tagScript.contains("tag id \"child-12345678901234567890\""))
    #expect(tagScript.contains("set keyboard shortcut of targetTag to \"\""))
    #expect(tagScript.contains("tag id \"parent-12345678901234567890\""))

    tag.parent = .clear
    let clearParentScript = try builder.script(for: .saveTag(tag))
    #expect(clearParentScript.contains("delete parent tag of targetTag"))
    #expect(!clearParentScript.contains("missing value"))
  }

  @Test("builds trash, restore, and maintenance commands")
  func lifecycleScripts() throws {
    let builder = ThingsAppleScriptBuilder()

    let trash = try builder.script(
      for: .trash(kind: .todo, id: "todo:todo-12345678901234567890"))
    #expect(trash.contains("delete to do id \"todo-12345678901234567890\""))

    let restoreTodo = try builder.script(
      for: .restore(
        kind: .todo,
        id: "todo:todo-12345678901234567890",
        destinations: [
          .project("project:project-12345678901234567890"),
          .area("area:area-12345678901234567890"),
          .builtin("Inbox"),
        ]
      ))
    #expect(restoreTodo.contains("first to do of list id \"TMTrashListSource\""))
    #expect(
      restoreTodo.contains(
        "set project of targetItem to project id \"project-12345678901234567890\""))
    #expect(
      restoreTodo.contains("move targetItem to area id \"area-12345678901234567890\""))
    #expect(restoreTodo.contains("move targetItem to list id \"TMInboxListSource\""))
    #expect(
      restoreTodo.contains(
        "if \"todo-12345678901234567890\" is not in (id of every to do of list id \"TMTrashListSource\") then set didRestore to true"
      ))
    #expect(restoreTodo.components(separatedBy: "if didRestore is false then").count == 5)

    let restoreProject = try builder.script(
      for: .restore(
        kind: .project,
        id: "project:project-12345678901234567890",
        destinations: [
          .area("area:area-12345678901234567890"),
          .builtin("Anytime"),
        ]
      ))
    #expect(restoreProject.contains("first project of list id \"TMTrashListSource\""))
    #expect(restoreProject.contains("move targetItem to area id"))
    #expect(restoreProject.contains("move targetItem to list id \"TMNextListSource\""))

    do {
      _ = try builder.script(
        for: .restore(
          kind: .project,
          id: "project:project-12345678901234567890",
          destinations: [.project("project:parent-12345678901234567890")]
        ))
      Issue.record("Expected a project destination to be rejected for project restore")
    } catch let error as ThingsAutomationError {
      #expect(error.errorDescription?.contains("cannot be restored inside another project") == true)
    }

    #expect(try builder.script(for: .emptyTrash).contains("empty trash"))
    #expect(try builder.script(for: .logCompleted).contains("log completed now"))
  }

  @Test("confirms Trash versus permanent delete semantics")
  func lifecycleResults() async throws {
    let executor = WorkspaceThingsAutomationExecutor(runner: StubThingsAppleScriptRunner())

    let todo = try await executor.execute(.trash(kind: .todo, id: "todo-id"))
    #expect(todo.action == "trash")
    #expect(todo.message.contains("moved"))

    let area = try await executor.execute(.trash(kind: .area, id: "area-id"))
    #expect(area.action == "delete")
    #expect(area.message.contains("permanently deleted"))
    #expect(area.message.contains("items were moved"))

    let tag = try await executor.execute(.trash(kind: .tag, id: "tag-id"))
    #expect(tag.action == "delete")
    #expect(tag.message.contains("permanently deleted"))
  }

  @Test("warns when a directory write can have partially applied")
  func partialDirectoryWriteWarning() async throws {
    var request = ThingsTagAutomationRequest()
    request.title = "Focus"
    request.shortcut = .value("f")
    let executor = WorkspaceThingsAutomationExecutor(runner: FailingThingsAppleScriptRunner())

    do {
      _ = try await executor.execute(.saveTag(request))
      Issue.record("Expected the directory write to fail")
    } catch let error as ThingsAutomationError {
      #expect(error.errorDescription?.contains("may have partially applied") == true)
      #expect(error.errorDescription?.contains("Read the object back") == true)
    }
  }

  @Test("serializes AppleScript execution off the caller")
  func serialExecution() async throws {
    let runner = SerialProbeThingsAppleScriptRunner()
    let executor = WorkspaceThingsAutomationExecutor(runner: runner)

    async let first = executor.execute(.logCompleted)
    async let second = executor.execute(.emptyTrash)
    _ = try await (first, second)

    #expect(runner.maximumConcurrentExecutions == 1)
  }
}

private struct StubThingsAppleScriptRunner: ThingsAppleScriptRunning {
  func execute(_ source: String) throws -> String? {
    "ok"
  }
}

private struct FailingThingsAppleScriptRunner: ThingsAppleScriptRunning {
  func execute(_ source: String) throws -> String? {
    throw ThingsAutomationError.scriptFailed("shortcut rejected")
  }
}

private final class SerialProbeThingsAppleScriptRunner: ThingsAppleScriptRunning,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var activeExecutions = 0
  private var maximumExecutions = 0

  var maximumConcurrentExecutions: Int {
    lock.withLock { maximumExecutions }
  }

  func execute(_ source: String) throws -> String? {
    lock.withLock {
      activeExecutions += 1
      maximumExecutions = max(maximumExecutions, activeExecutions)
    }
    Thread.sleep(forTimeInterval: 0.02)
    lock.withLock {
      activeExecutions -= 1
    }
    return "ok"
  }
}
