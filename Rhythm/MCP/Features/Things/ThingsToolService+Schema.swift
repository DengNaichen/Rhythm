import Foundation
import JSONSchema

extension ThingsToolService {
  func enumSchema<T: RawRepresentable & CaseIterable>(
    _ type: T.Type,
    excluding excluded: Set<String> = [],
    description: String,
    defaultValue: String? = nil
  ) -> JSONSchema where T.RawValue == String {
    let values: [JSONValue] = T.allCases
      .map(\.rawValue)
      .filter { !excluded.contains($0) }
      .map(JSONValue.string)
    let defaultJSONValue = defaultValue.map(JSONValue.string)
    return .string(
      description: description,
      default: defaultJSONValue,
      enum: values
    )
  }

  func enumSchema<T: RawRepresentable & CaseIterable & Hashable>(
    _ type: T.Type,
    excluding excluded: Set<T>,
    description: String
  ) -> JSONSchema where T.RawValue == String {
    enumSchema(
      type,
      excluding: Set(excluded.map(\.rawValue)),
      description: description
    )
  }

  func dateSchema(_ description: String) -> JSONSchema {
    .string(description: description, format: .date)
  }

  func nullableStringSchema(_ description: String) -> JSONSchema {
    .anyOf([.string(description: description), .null])
  }

  func nullableStringArraySchema(
    _ description: String,
    maxItems: Int? = nil
  ) -> JSONSchema {
    .anyOf([
      .array(description: description, items: .string(), maxItems: maxItems), .null,
    ])
  }

  func pageLimitSchema() -> JSONSchema {
    .integer(
      description: "Maximum results to return.",
      default: .int(ThingsPageRequest.defaultLimit),
      minimum: 1,
      maximum: ThingsPageRequest.maximumLimit
    )
  }
}
