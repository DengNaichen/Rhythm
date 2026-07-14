import Foundation
import JSONSchema
import MCP
import Ontology

struct Tool: Identifiable {
  let name: String
  let title: String
  let description: String
  let systemImage: String
  let inputSchema: JSONSchema?
  let annotations: MCP.Tool.Annotations

  private let implementation: ([String: Value]) async throws -> Value

  var id: String { name }

  init<T: Encodable>(
    name: String,
    title: String,
    description: String,
    systemImage: String,
    inputSchema: JSONSchema? = nil,
    readOnlyHint: Bool = false,
    destructiveHint: Bool = false,
    idempotentHint: Bool? = nil,
    openWorldHint: Bool = false,
    implementation: @escaping ([String: Value]) async throws -> T
  ) {
    self.name = name
    self.title = title
    self.description = description
    self.systemImage = systemImage
    self.inputSchema = inputSchema
    self.annotations = .init(
      title: title,
      readOnlyHint: readOnlyHint ? true : nil,
      destructiveHint: readOnlyHint ? nil : destructiveHint,
      idempotentHint: idempotentHint,
      openWorldHint: openWorldHint
    )
    self.implementation = { input in
      if let inputSchema {
        try ToolInputValidator.validate(input, against: inputSchema)
      }
      let result = try await implementation(input)
      let encoder = JSONEncoder()
      encoder.userInfo[Ontology.DateTime.timeZoneOverrideKey] = TimeZone.current
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

      let data = try encoder.encode(result)
      return try JSONDecoder().decode(Value.self, from: data)
    }
  }

  var mcpDefinition: MCP.Tool {
    MCP.Tool(
      name: name,
      title: title,
      description: description,
      inputSchema: mcpInputSchema,
      annotations: annotations
    )
  }

  func callAsFunction(_ input: [String: Value]) async throws -> Value {
    try await implementation(input)
  }

  private var mcpInputSchema: Value {
    guard let inputSchema else {
      return .object(["type": .string("object")])
    }

    do {
      return try Value(inputSchema)
    } catch {
      assertionFailure("Failed to convert tool schema for \(name): \(error)")
      return .object(["type": .string("object")])
    }
  }
}
