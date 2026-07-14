@testable import Rhythm

actor ThingsAutomationExecutorSpy: ThingsAutomationExecuting {
  var commands: [ThingsAutomationCommand] = []

  func execute(_ command: ThingsAutomationCommand) async throws -> ThingsAutomationResult {
    commands.append(command)
    switch command {
    case .saveArea(let request):
      return ThingsAutomationResult(
        action: request.isCreate ? "create" : "update",
        type: .area,
        ref: request.id ?? "area:new-area",
        confirmed: true,
        message: "Area saved."
      )
    case .saveTag(let request):
      return ThingsAutomationResult(
        action: request.isCreate ? "create" : "update",
        type: .tag,
        ref: request.id ?? "tag:new-tag",
        confirmed: true,
        message: "Tag saved."
      )
    case .trash(let kind, let id):
      return ThingsAutomationResult(
        action: "trash",
        type: kind,
        ref: ThingsEntityID.make(kind, rawID: id),
        confirmed: true,
        message: "Deleted."
      )
    case .restore(let kind, let id, _):
      return ThingsAutomationResult(
        action: "restore",
        type: kind,
        ref: ThingsEntityID.make(kind, rawID: id),
        confirmed: true,
        message: "Restored."
      )
    case .emptyTrash:
      return ThingsAutomationResult(
        action: "empty_trash",
        type: nil,
        ref: nil,
        confirmed: true,
        message: "Trash emptied."
      )
    case .logCompleted:
      return ThingsAutomationResult(
        action: "log_completed",
        type: nil,
        ref: nil,
        confirmed: true,
        message: "Logged."
      )
    }
  }
}
