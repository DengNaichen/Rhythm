import AppKit
import Foundation

nonisolated enum ThingsRestoreDestination: Equatable, Sendable {
  case builtin(String)
  case area(String)
  case project(String)
}

nonisolated enum ThingsAutomationCommand: Equatable, Sendable {
  case saveArea(ThingsAreaAutomationRequest)
  case saveTag(ThingsTagAutomationRequest)
  case trash(kind: ThingsEntityKind, id: String)
  case restore(
    kind: ThingsEntityKind,
    id: String,
    destinations: [ThingsRestoreDestination]
  )
  case emptyTrash
  case logCompleted
}

nonisolated struct ThingsAreaAutomationRequest: Equatable, Sendable {
  var id: String?
  var title: String?
  var tags: ThingsPatch<[String]> = .unchanged
  var collapsed: Bool?

  var isCreate: Bool { id == nil }
}

nonisolated struct ThingsTagAutomationRequest: Equatable, Sendable {
  var id: String?
  var title: String?
  var shortcut: ThingsPatch<String> = .unchanged
  var parent: ThingsPatch<String> = .unchanged

  var isCreate: Bool { id == nil }
}

nonisolated struct ThingsAutomationResult: Encodable, Equatable, Sendable {
  let action: String
  let type: ThingsEntityKind?
  let ref: String?
  let confirmed: Bool
  let message: String
}

nonisolated protocol ThingsAutomationExecuting: AnyObject, Sendable {
  func execute(_ command: ThingsAutomationCommand) async throws -> ThingsAutomationResult
}

nonisolated enum ThingsAutomationError: Error, LocalizedError, Sendable {
  case unsupportedEntity(ThingsEntityKind)
  case invalidCommand(String)
  case scriptFailed(String)
  case partialWritePossible(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedEntity(let kind):
      return "Things AppleScript does not support this operation for \(kind.rawValue)."
    case .invalidCommand(let reason):
      return "Invalid Things automation command: \(reason)"
    case .scriptFailed(let message):
      return "Things automation failed: \(message)"
    case .partialWritePossible(let message):
      return
        "Things area/tag write failed and may have partially applied: \(message) Read the object back before retrying."
    }
  }
}

nonisolated protocol ThingsAppleScriptRunning: Sendable {
  func execute(_ source: String) throws -> String?
}

nonisolated struct WorkspaceThingsAppleScriptRunner: ThingsAppleScriptRunning {
  func execute(_ source: String) throws -> String? {
    guard let script = NSAppleScript(source: source) else {
      throw ThingsAutomationError.scriptFailed("Could not compile the AppleScript source.")
    }

    var errorInfo: NSDictionary?
    let descriptor = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        errorInfo[NSAppleScript.errorMessage] as? String
        ?? errorInfo.description
      throw ThingsAutomationError.scriptFailed(message)
    }
    return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

actor WorkspaceThingsAutomationExecutor: ThingsAutomationExecuting {
  private let builder: ThingsAppleScriptBuilder
  private let runner: any ThingsAppleScriptRunning

  init(
    builder: ThingsAppleScriptBuilder = ThingsAppleScriptBuilder(),
    runner: any ThingsAppleScriptRunning = WorkspaceThingsAppleScriptRunner()
  ) {
    self.builder = builder
    self.runner = runner
  }

  func execute(_ command: ThingsAutomationCommand) async throws -> ThingsAutomationResult {
    let source = try builder.script(for: command)
    let returnedID: String?
    do {
      returnedID = try runner.execute(source)
    } catch ThingsAutomationError.scriptFailed(let message) {
      switch command {
      case .saveArea, .saveTag:
        throw ThingsAutomationError.partialWritePossible(message)
      case .trash, .restore, .emptyTrash, .logCompleted:
        throw ThingsAutomationError.scriptFailed(message)
      }
    }
    return try result(for: command, returnedID: returnedID)
  }

  private func result(
    for command: ThingsAutomationCommand,
    returnedID: String?
  ) throws -> ThingsAutomationResult {
    switch command {
    case .saveArea(let request):
      let rawID = try requiredReturnedID(returnedID, fallback: request.id)
      return ThingsAutomationResult(
        action: request.isCreate ? "create" : "update",
        type: .area,
        ref: ThingsEntityID.make(.area, rawID: rawID),
        confirmed: true,
        message: request.isCreate ? "Area created in Things." : "Area updated in Things."
      )
    case .saveTag(let request):
      let rawID = try requiredReturnedID(returnedID, fallback: request.id)
      return ThingsAutomationResult(
        action: request.isCreate ? "create" : "update",
        type: .tag,
        ref: ThingsEntityID.make(.tag, rawID: rawID),
        confirmed: true,
        message: request.isCreate ? "Tag created in Things." : "Tag updated in Things."
      )
    case .trash(let kind, let id):
      switch kind {
      case .todo, .project:
        return ThingsAutomationResult(
          action: "trash",
          type: kind,
          ref: ThingsEntityID.make(kind, rawID: id),
          confirmed: true,
          message: "Item moved to the Things Trash."
        )
      case .area:
        return ThingsAutomationResult(
          action: "delete",
          type: kind,
          ref: ThingsEntityID.make(kind, rawID: id),
          confirmed: true,
          message: "Area permanently deleted; its items were moved to the Things Trash."
        )
      case .tag:
        return ThingsAutomationResult(
          action: "delete",
          type: kind,
          ref: ThingsEntityID.make(kind, rawID: id),
          confirmed: true,
          message: "Tag permanently deleted from Things."
        )
      case .heading, .all:
        throw ThingsAutomationError.unsupportedEntity(kind)
      }
    case .restore(let kind, let id, _):
      return ThingsAutomationResult(
        action: "restore",
        type: kind,
        ref: ThingsEntityID.make(kind, rawID: id),
        confirmed: true,
        message: "Item restored from the Things Trash."
      )
    case .emptyTrash:
      return ThingsAutomationResult(
        action: "empty_trash",
        type: nil,
        ref: nil,
        confirmed: true,
        message: "Things Trash emptied."
      )
    case .logCompleted:
      return ThingsAutomationResult(
        action: "log_completed",
        type: nil,
        ref: nil,
        confirmed: true,
        message: "Completed items logged in Things."
      )
    }
  }

  private func requiredReturnedID(_ value: String?, fallback: String?) throws -> String {
    if let value, !value.isEmpty { return value }
    if let fallback { return ThingsEntityID.parse(fallback).rawID }
    throw ThingsAutomationError.scriptFailed("Things did not return the new object's ID.")
  }
}

nonisolated struct ThingsAppleScriptBuilder {
  func script(for command: ThingsAutomationCommand) throws -> String {
    let statements: [String]
    switch command {
    case .saveArea(let request):
      statements = try areaStatements(request)
    case .saveTag(let request):
      statements = try tagStatements(request)
    case .trash(let kind, let id):
      statements = ["delete \(try itemSpecifier(kind: kind, id: id))", "return \"ok\""]
    case .restore(let kind, let id, let destinations):
      statements = try restoreStatements(kind: kind, id: id, destinations: destinations)
    case .emptyTrash:
      statements = ["empty trash", "return \"ok\""]
    case .logCompleted:
      statements = ["log completed now", "return \"ok\""]
    }

    let body = statements.map { "  \($0)" }.joined(separator: "\n")
    return """
      tell application id "com.culturedcode.ThingsMac"
      \(body)
      end tell
      """
  }

  private func areaStatements(_ request: ThingsAreaAutomationRequest) throws -> [String] {
    var statements: [String] = []
    if let id = request.id {
      statements.append("set targetArea to area id \(literal(try rawID(id, kind: .area)))")
    } else {
      guard let title = request.title, !title.isEmpty else {
        throw ThingsAutomationError.invalidCommand("title is required when creating an area")
      }
      statements.append("set targetArea to make new area with properties {name:\(literal(title))}")
    }

    if let title = request.title {
      statements.append("set name of targetArea to \(literal(title))")
    }
    switch request.tags {
    case .unchanged:
      break
    case .clear:
      statements.append("set tag names of targetArea to \"\"")
    case .value(let tags):
      statements.append("set tag names of targetArea to \(literal(tags.joined(separator: ", ")))")
    }
    if let collapsed = request.collapsed {
      statements.append("set collapsed of targetArea to \(collapsed ? "true" : "false")")
    }
    statements.append("return id of targetArea")
    return statements
  }

  private func tagStatements(_ request: ThingsTagAutomationRequest) throws -> [String] {
    var statements: [String] = []
    if let id = request.id {
      statements.append("set targetTag to tag id \(literal(try rawID(id, kind: .tag)))")
    } else {
      guard let title = request.title, !title.isEmpty else {
        throw ThingsAutomationError.invalidCommand("title is required when creating a tag")
      }
      statements.append("set targetTag to make new tag with properties {name:\(literal(title))}")
    }

    if let title = request.title {
      statements.append("set name of targetTag to \(literal(title))")
    }
    switch request.shortcut {
    case .unchanged:
      break
    case .clear:
      statements.append("set keyboard shortcut of targetTag to \"\"")
    case .value(let shortcut):
      statements.append("set keyboard shortcut of targetTag to \(literal(shortcut))")
    }
    switch request.parent {
    case .unchanged:
      break
    case .clear:
      statements.append("delete parent tag of targetTag")
    case .value(let parent):
      statements.append(
        "set parent tag of targetTag to tag id \(literal(try rawID(parent, kind: .tag)))")
    }
    statements.append("return id of targetTag")
    return statements
  }

  private func restoreStatements(
    kind: ThingsEntityKind,
    id: String,
    destinations: [ThingsRestoreDestination]
  ) throws -> [String] {
    let className: String
    let effectiveDestinations: [ThingsRestoreDestination]
    switch kind {
    case .todo:
      className = "to do"
      effectiveDestinations = destinations.isEmpty ? [.builtin("Inbox")] : destinations
    case .project:
      className = "project"
      effectiveDestinations = destinations.isEmpty ? [.builtin("Anytime")] : destinations
    case .heading, .area, .tag, .all:
      throw ThingsAutomationError.unsupportedEntity(kind)
    }

    let rawItemID = try rawID(id, kind: kind)
    let trashListSpecifier = try builtinListSpecifier("Trash")
    let trashItemSpecifier =
      "first \(className) of \(trashListSpecifier) whose id is \(literal(rawItemID))"
    var statements = [
      "set targetItem to \(trashItemSpecifier)",
      "set didRestore to false",
    ]
    for destination in effectiveDestinations {
      let operation = try restoreOperation(targetKind: kind, destination: destination)
      statements.append(contentsOf: [
        "if didRestore is false then",
        "  try",
        "    \(operation)",
        "    if \(literal(rawItemID)) is not in (id of every \(className) of \(trashListSpecifier)) then set didRestore to true",
        "  end try",
        "end if",
      ])
    }
    statements.append(contentsOf: [
      "if didRestore is false then error \"Could not restore the item to any requested destination.\"",
      "return \"ok\"",
    ])
    return statements
  }

  private func restoreOperation(
    targetKind: ThingsEntityKind,
    destination: ThingsRestoreDestination
  ) throws -> String {
    switch destination {
    case .builtin(let name):
      return "move targetItem to \(try builtinListSpecifier(name))"
    case .area(let id):
      return "move targetItem to area id \(literal(try rawID(id, kind: .area)))"
    case .project(let id):
      guard targetKind == .todo else {
        throw ThingsAutomationError.invalidCommand(
          "a project cannot be restored inside another project")
      }
      return "set project of targetItem to project id \(literal(try rawID(id, kind: .project)))"
    }
  }

  private func itemSpecifier(kind: ThingsEntityKind, id: String) throws -> String {
    let className: String
    switch kind {
    case .todo:
      className = "to do"
    case .project:
      className = "project"
    case .area:
      className = "area"
    case .tag:
      className = "tag"
    case .heading, .all:
      throw ThingsAutomationError.unsupportedEntity(kind)
    }
    return "\(className) id \(literal(try rawID(id, kind: kind)))"
  }

  private func builtinListSpecifier(_ name: String) throws -> String {
    let identifiers = [
      "inbox": "TMInboxListSource",
      "today": "TMTodayListSource",
      "anytime": "TMNextListSource",
      "someday": "TMSomedayListSource",
      "logbook": "TMLogbookListSource",
      "trash": "TMTrashListSource",
    ]
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let identifier = identifiers[normalized] else {
      throw ThingsAutomationError.invalidCommand("unsupported restore built-in list: \(name)")
    }
    return "list id \(literal(identifier))"
  }

  private func rawID(_ value: String, kind: ThingsEntityKind) throws -> String {
    try ThingsEntityID.rawID(value, expectedKind: kind)
  }

  private func literal(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }
}
