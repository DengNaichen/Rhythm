import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func batchTool() -> Tool {
    Tool(
      name: "things_batch",
      title: "Batch Things Changes",
      description:
        "Create or update multiple todos and projects through Things JSON, including project headings and checklist row statuses.",
      systemImage: "square.stack.3d.up",
      inputSchema: .object(
        properties: [
          "items": .array(
            description: "Official Things JSON operations.",
            items: batchItemSchema(),
            minItems: 1,
            maxItems: 250
          ),
          "reveal": .boolean(
            description: "Reveal the first created item after applying the batch.", default: false),
        ],
        required: ["items"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      guard let values = try decoder.optionalArray("items"), !values.isEmpty else {
        throw ThingsServiceError.missingRequiredArgument("items")
      }
      guard values.count <= 250 else {
        throw ThingsServiceError.invalidValue("items", reason: "maximum batch size is 250")
      }

      try self.validateJSONValueShapes(values)
      let data = try JSONEncoder().encode(values)
      let items: [ThingsJSONItem]
      do {
        items = try JSONDecoder().decode([ThingsJSONItem].self, from: data)
      } catch {
        throw ThingsServiceError.invalidValue("items", reason: error.localizedDescription)
      }
      try self.validateJSONItems(items)
      try await self.validateJSONTags(items)
      try await self.validateJSONReferences(items)

      let requiresToken = items.contains { $0.operation == .update }
      let token: String?
      if requiresToken {
        try await self.activate()
        token = try self.repository.authToken()
      } else {
        token = nil
      }
      try self.validateJSONUpdateSemantics(items)
      try self.validateJSONChecklistLimits(items)
      let request = ThingsJSONCommandRequest(
        items: items,
        authToken: token,
        reveal: try decoder.optionalBool("reveal") ?? false
      )
      let callback = try await self.callbackExecutor.execute(
        try self.urlBuilder.jsonURL(for: request))

      let createdItems = items.filter { $0.operation == .create }
      let refs = zip(createdItems, callback.thingsIDs).map { item, id in
        ThingsEntityID.make(item.entityKind, rawID: id)
      }
      return ThingsBatchResult(
        operationCount: items.count,
        createdCount: refs.count,
        refs: refs,
        acknowledged: true,
        verified: false,
        parameters: callback.parameters,
        message:
          "Things acknowledged the batch command. Read affected items back to verify applied fields."
      )
    }
  }

  private func batchItemSchema() -> JSONSchema {
    let standardString = JSONSchema.string(maxLength: 4_000)
    let notesString = JSONSchema.string(maxLength: 10_000)
    let checklistItem = JSONSchema.object(
      properties: [
        "type": .string(enum: [.string("checklist-item")]),
        "attributes": .object(
          properties: [
            "title": standardString,
            "completed": .boolean(),
            "canceled": .boolean(),
          ],
          additionalProperties: false
        ),
      ],
      required: ["type", "attributes"],
      additionalProperties: false
    )
    let todoAttributes = JSONSchema.object(
      properties: [
        "title": standardString,
        "notes": notesString,
        "when": standardString,
        "deadline": standardString,
        "tags": .array(items: standardString),
        "checklist-items": .array(items: checklistItem, maxItems: 100),
        "list-id": standardString,
        "list": standardString,
        "heading-id": standardString,
        "heading": standardString,
        "completed": .boolean(),
        "canceled": .boolean(),
        "creation-date": standardString,
        "completion-date": standardString,
        "prepend-notes": notesString,
        "append-notes": notesString,
        "add-tags": standardString,
        "prepend-checklist-items": standardString,
        "append-checklist-items": standardString,
      ],
      additionalProperties: false
    )
    let heading = JSONSchema.object(
      properties: [
        "type": .string(enum: [.string("heading")]),
        "attributes": .object(
          properties: [
            "title": standardString,
            "archived": .boolean(),
          ],
          additionalProperties: false
        ),
      ],
      required: ["type", "attributes"],
      additionalProperties: false
    )
    let childTodo = JSONSchema.object(
      properties: [
        "type": .string(enum: [.string("to-do")]),
        "attributes": todoAttributes,
      ],
      required: ["type", "attributes"],
      additionalProperties: false
    )
    let projectAttributes = JSONSchema.object(
      properties: [
        "title": standardString,
        "notes": notesString,
        "when": standardString,
        "deadline": standardString,
        "tags": .array(items: standardString),
        "area-id": standardString,
        "area": standardString,
        "completed": .boolean(),
        "canceled": .boolean(),
        "creation-date": standardString,
        "completion-date": standardString,
        "items": .array(items: .anyOf([childTodo, heading]), maxItems: 250),
        "prepend-notes": notesString,
        "append-notes": notesString,
        "add-tags": standardString,
      ],
      additionalProperties: false
    )
    let operation = JSONSchema.string(
      enum: [
        .string(ThingsJSONOperation.create.rawValue),
        .string(ThingsJSONOperation.update.rawValue),
      ]
    )
    let todo = JSONSchema.object(
      properties: [
        "type": .string(enum: [.string("to-do")]),
        "operation": operation,
        "id": standardString,
        "attributes": todoAttributes,
      ],
      required: ["type", "attributes"],
      additionalProperties: false
    )
    let project = JSONSchema.object(
      properties: [
        "type": .string(enum: [.string("project")]),
        "operation": operation,
        "id": standardString,
        "attributes": projectAttributes,
      ],
      required: ["type", "attributes"],
      additionalProperties: false
    )
    return .anyOf([todo, project])
  }
}

private struct ThingsBatchResult: Encodable, Sendable {
  let operationCount: Int
  let createdCount: Int
  let refs: [String]
  let acknowledged: Bool
  let verified: Bool
  let parameters: [String: [String]]
  let message: String

  enum CodingKeys: String, CodingKey {
    case operationCount = "operation_count"
    case createdCount = "created_count"
    case refs
    case acknowledged
    case verified
    case parameters
    case message
  }
}

extension ThingsJSONItem {
  var entityKind: ThingsEntityKind {
    switch self {
    case .todo:
      return .todo
    case .project:
      return .project
    }
  }
}
