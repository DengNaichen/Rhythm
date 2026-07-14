import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func trashTool() -> Tool {
    Tool(
      name: "things_delete",
      title: "Delete Things Entity",
      description:
        "Move a todo or project to Trash, or permanently delete an area/tag. Deleting an area affects its items; deleting a parent tag also deletes its child tags.",
      systemImage: "trash",
      inputSchema: .object(
        properties: [
          "ref": .string(
            description: "Typed reference: todo:<id>, project:<id>, area:<id>, or tag:<id>."),
          "confirm_cascade": .boolean(
            description:
              "Required for area deletion and for deleting a parent tag with child tags.",
            default: false
          ),
          "confirm_permanent": .boolean(
            description: "Required for tag deletion because the tag is permanently deleted.",
            default: false
          ),
        ],
        required: ["ref"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      let reference = try decoder.requiredString("ref")
      let parsed = ThingsEntityID.parse(reference)
      guard let kind = parsed.kind, [.todo, .project, .area, .tag].contains(kind) else {
        throw ThingsServiceError.invalidValue(
          "ref", reason: "a typed todo, project, area, or tag reference is required")
      }
      if kind == .area, try decoder.optionalBool("confirm_cascade") != true {
        throw ThingsServiceError.invalidValue(
          "confirm_cascade", reason: "must be true when deleting an area")
      }
      if kind == .tag, try decoder.optionalBool("confirm_permanent") != true {
        throw ThingsServiceError.invalidValue(
          "confirm_permanent", reason: "must be true when permanently deleting a tag")
      }
      try await self.activate()
      let entity = try self.repository.fetch(reference, includeItems: false)
      if kind == .tag, case .tag(let tag) = entity, !tag.children.isEmpty,
        try decoder.optionalBool("confirm_cascade") != true
      {
        throw ThingsServiceError.invalidValue(
          "confirm_cascade",
          reason: "must be true because deleting this parent tag also deletes its child tags"
        )
      }
      return try await self.automationExecutor.execute(.trash(kind: kind, id: parsed.rawID))
    }
  }

  func restoreTool() -> Tool {
    Tool(
      name: "things_restore",
      title: "Restore Things Item",
      description:
        "Restore a trashed todo or project. By default Rhythm restores it to its recorded parent, then Inbox/Anytime as a fallback.",
      systemImage: "arrow.uturn.backward.circle",
      inputSchema: .object(
        properties: [
          "ref": .string(description: "Typed todo:<id> or project:<id> reference."),
          "destination": .string(
            description: "Optional project/area reference or built-in list name."),
        ],
        required: ["ref"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      try await self.activate()
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      let reference = try decoder.requiredString("ref")
      let parsed = ThingsEntityID.parse(reference)
      guard let kind = parsed.kind, kind == .todo || kind == .project else {
        throw ThingsServiceError.invalidValue(
          "ref", reason: "a typed todo or project reference is required")
      }
      let entity = try self.repository.fetch(reference, includeItems: false)
      let explicitDestination = try decoder.optionalString("destination")
      let destinations: [ThingsRestoreDestination]
      if let explicitDestination {
        destinations = [try self.explicitRestoreDestination(explicitDestination, kind: kind)]
      } else {
        destinations = try self.restoreDestinations(for: entity)
      }
      return try await self.automationExecutor.execute(
        .restore(kind: kind, id: parsed.rawID, destinations: destinations))
    }
  }

  func emptyTrashTool() -> Tool {
    Tool(
      name: "things_empty_trash",
      title: "Empty Things Trash",
      description: "Permanently delete every item currently in Things Trash.",
      systemImage: "trash.slash",
      inputSchema: .object(
        properties: [
          "confirm": .boolean(description: "Must be true to permanently empty Trash.")
        ],
        required: ["confirm"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      guard try ToolArgumentsDecoder(arguments: arguments).optionalBool("confirm") == true else {
        throw ThingsServiceError.invalidValue("confirm", reason: "must be true")
      }
      return try await self.automationExecutor.execute(.emptyTrash)
    }
  }

  func logCompletedTool() -> Tool {
    Tool(
      name: "things_log_completed",
      title: "Log Completed Things Items",
      description: "Move currently completed items into the Things Logbook now.",
      systemImage: "archivebox",
      inputSchema: .object(additionalProperties: false),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { _ in
      try await self.automationExecutor.execute(.logCompleted)
    }
  }

  private func restoreDestinations(for entity: ThingsEntity) throws
    -> [ThingsRestoreDestination]
  {
    switch entity {
    case .todo(let todo):
      var destinations: [ThingsRestoreDestination] = []
      if let project = todo.project, try isActiveRestoreProject(project.id) {
        destinations.append(.project(project.id))
      } else if let area = todo.area {
        destinations.append(.area(area.id))
      }
      destinations.append(.builtin("Inbox"))
      return destinations
    case .project(let project):
      var destinations: [ThingsRestoreDestination] = []
      if let area = project.area {
        destinations.append(.area(area.id))
      }
      destinations.append(.builtin("Anytime"))
      return destinations
    case .heading, .area, .tag:
      return []
    }
  }

  private func isActiveRestoreProject(_ reference: String) throws -> Bool {
    do {
      let entity = try repository.fetch(reference, includeItems: false)
      guard case .project(let project) = entity else { return false }
      return project.list?.lowercased() != ThingsBuiltinList.trash.rawValue
    } catch ThingsServiceError.entityNotFound {
      return false
    }
  }

  private func explicitRestoreDestination(
    _ value: String,
    kind: ThingsEntityKind
  ) throws -> ThingsRestoreDestination {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let builtins = [
      "inbox": "Inbox",
      "today": "Today",
      "anytime": "Anytime",
      "someday": "Someday",
      "logbook": "Logbook",
    ]
    if let builtin = builtins[normalized.lowercased()] {
      return .builtin(builtin)
    }

    let parsed = ThingsEntityID.parse(normalized)
    switch parsed.kind {
    case .area:
      _ = try repository.fetch(normalized, includeItems: false)
      return .area(normalized)
    case .project where kind == .todo:
      let entity = try repository.fetch(normalized, includeItems: false)
      guard case .project(let project) = entity,
        project.list?.lowercased() != ThingsBuiltinList.trash.rawValue
      else {
        throw ThingsServiceError.invalidValue(
          "destination", reason: "the destination project is in Trash; restore it first")
      }
      return .project(normalized)
    case .project:
      throw ThingsServiceError.invalidValue(
        "destination", reason: "a project cannot be restored inside another project")
    case .todo, .heading, .tag, .all:
      throw ThingsServiceError.invalidValue(
        "destination", reason: "expected an area/project reference or a movable built-in list")
    case nil:
      throw ThingsServiceError.invalidValue(
        "destination",
        reason: "use a typed area:<id> or project:<id> reference, or a movable built-in list"
      )
    }
  }
}
