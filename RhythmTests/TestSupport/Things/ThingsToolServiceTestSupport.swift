import Foundation
import MCP

@testable import Rhythm

@MainActor
func makeThingsService(
  repository: ThingsRepositorySpy? = nil,
  builder: ThingsURLBuilderSpy = ThingsURLBuilderSpy(),
  callback: ThingsCallbackExecutorSpy = ThingsCallbackExecutorSpy(),
  automation: ThingsAutomationExecutorSpy? = nil
) -> ThingsToolService {
  ThingsToolService(
    urlBuilder: builder,
    callbackExecutor: callback,
    automationExecutor: automation ?? ThingsAutomationExecutorSpy(),
    repository: repository ?? ThingsRepositorySpy()
  )
}

func thingsCallback(
  _ parameters: [String: [String]]
) -> ThingsCallbackSuccess {
  ThingsCallbackSuccess(requestID: UUID(), parameters: parameters)
}

@MainActor
func referenceThingsRepository() -> ThingsRepositorySpy {
  let repository = ThingsRepositorySpy()
  repository.projects = [ThingsTestFixtures.projectOne, ThingsTestFixtures.projectTwo]
  repository.heading = ThingsTestFixtures.heading
  repository.fetchedEntities[ThingsTestFixtures.area.id] = .area(ThingsTestFixtures.area)
  return repository
}

func batchTodoValue(listID: String, headingID: String? = nil) -> Value {
  var attributes: [String: Value] = [
    "title": .string("Todo"),
    "list-id": .string(listID),
  ]
  if let headingID {
    attributes["heading-id"] = .string(headingID)
  }
  return .object([
    "type": .string("to-do"),
    "attributes": .object(attributes),
  ])
}

func batchProjectValue(areaID: String) -> Value {
  .object([
    "type": .string("project"),
    "attributes": .object([
      "title": .string("Project"),
      "area-id": .string(areaID),
    ]),
  ])
}
