import Foundation
import JSONSchema
import MCP
import OrderedCollections

nonisolated enum ToolInputValidator {
  static func validate(_ input: [String: Value], against schema: JSONSchema) throws {
    try validate(.object(input), against: schema, path: "arguments")
  }

  private static func validate(_ value: Value, against schema: JSONSchema, path: String) throws {
    switch schema {
    case .object(
      _, _, _, _, let allowedValues, let constant, let properties, let required,
      let additionalProperties
    ):
      guard case .object(let object) = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "object")
      }
      try validateAllowed(value, enum: allowedValues, const: constant, path: path)
      for key in required where object[key] == nil {
        throw ServiceToolError.missingRequiredArgument(qualified(path, key))
      }
      for (key, child) in object {
        if let propertySchema = properties[key] {
          try validate(child, against: propertySchema, path: qualified(path, key))
          continue
        }
        switch additionalProperties {
        case .boolean(false):
          throw ServiceToolError.invalidValue(
            argument: qualified(path, key), reason: "unknown argument")
        case .schema(let additionalSchema):
          try validate(child, against: additionalSchema, path: qualified(path, key))
        case .boolean(true), nil:
          break
        }
      }

    case .array(
      _, _, _, _, let allowedValues, let constant, let itemSchema, let minimum, let maximum,
      let unique
    ):
      guard case .array(let values) = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "array")
      }
      try validateAllowed(value, enum: allowedValues, const: constant, path: path)
      if let minimum, values.count < minimum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "requires at least \(minimum) items")
      }
      if let maximum, values.count > maximum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "allows at most \(maximum) items")
      }
      if unique == true, Set(values).count != values.count {
        throw ServiceToolError.invalidValue(argument: path, reason: "items must be unique")
      }
      if let itemSchema {
        for (index, child) in values.enumerated() {
          try validate(child, against: itemSchema, path: "\(path)[\(index)]")
        }
      }

    case .string(
      _, _, _, _, let allowedValues, let constant, let minimum, let maximum, let pattern,
      let format
    ):
      guard case .string(let string) = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "string")
      }
      try validateAllowed(value, enum: allowedValues, const: constant, path: path)
      if let minimum, string.count < minimum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must contain at least \(minimum) characters")
      }
      if let maximum, string.count > maximum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must contain at most \(maximum) characters")
      }
      if let pattern, string.range(of: pattern, options: .regularExpression) == nil {
        throw ServiceToolError.invalidValue(argument: path, reason: "does not match \(pattern)")
      }
      if let format, !matchesFormat(string, format: format) {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "expected \(format.rawValue) format")
      }

    case .number(
      _, _, _, _, let allowedValues, let constant, let minimum, let maximum,
      let exclusiveMinimum, let exclusiveMaximum, let multipleOf
    ):
      let number: Double
      switch value {
      case .int(let integer): number = Double(integer)
      case .double(let double): number = double
      default:
        throw ServiceToolError.invalidType(argument: path, expected: "number")
      }
      try validateAllowed(value, enum: allowedValues, const: constant, path: path)
      try validateNumber(
        number,
        path: path,
        minimum: minimum,
        maximum: maximum,
        exclusiveMinimum: exclusiveMinimum,
        exclusiveMaximum: exclusiveMaximum,
        multipleOf: multipleOf
      )

    case .integer(
      _, _, _, _, let allowedValues, let constant, let minimum, let maximum,
      let exclusiveMinimum, let exclusiveMaximum, let multipleOf
    ):
      guard case .int(let integer) = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "integer")
      }
      try validateAllowed(value, enum: allowedValues, const: constant, path: path)
      if let minimum, integer < minimum {
        throw ServiceToolError.invalidValue(argument: path, reason: "must be at least \(minimum)")
      }
      if let maximum, integer > maximum {
        throw ServiceToolError.invalidValue(argument: path, reason: "must be at most \(maximum)")
      }
      if let exclusiveMinimum, integer <= exclusiveMinimum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must be greater than \(exclusiveMinimum)")
      }
      if let exclusiveMaximum, integer >= exclusiveMaximum {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must be less than \(exclusiveMaximum)")
      }
      if let multipleOf, multipleOf != 0, integer % multipleOf != 0 {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must be a multiple of \(multipleOf)")
      }

    case .boolean:
      guard case .bool = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "boolean")
      }

    case .null:
      guard case .null = value else {
        throw ServiceToolError.invalidType(argument: path, expected: "null")
      }

    case .anyOf(let schemas):
      var firstError: Error?
      for childSchema in schemas {
        do {
          try validate(value, against: childSchema, path: path)
          return
        } catch {
          if firstError == nil { firstError = error }
        }
      }
      throw firstError
        ?? ServiceToolError.invalidValue(
          argument: path, reason: "does not match any allowed schema")

    case .allOf(let schemas):
      for childSchema in schemas {
        try validate(value, against: childSchema, path: path)
      }

    case .oneOf(let schemas):
      guard schemas.filter({ accepts(value, schema: $0, path: path) }).count == 1 else {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must match exactly one allowed schema")
      }

    case .not(let childSchema):
      guard !accepts(value, schema: childSchema, path: path) else {
        throw ServiceToolError.invalidValue(argument: path, reason: "matches a forbidden schema")
      }

    case .reference, .empty, .any:
      break
    }
  }

  private static func validateAllowed(
    _ value: Value,
    enum allowedValues: [JSONValue]?,
    const constant: JSONValue?,
    path: String
  ) throws {
    if let allowedValues, !allowedValues.contains(where: { equals(value, $0) }) {
      throw ServiceToolError.invalidValue(argument: path, reason: "value is not allowed")
    }
    if let constant, !equals(value, constant) {
      throw ServiceToolError.invalidValue(argument: path, reason: "value does not match const")
    }
  }

  private static func validateNumber(
    _ value: Double,
    path: String,
    minimum: Double?,
    maximum: Double?,
    exclusiveMinimum: Double?,
    exclusiveMaximum: Double?,
    multipleOf: Double?
  ) throws {
    if let minimum, value < minimum {
      throw ServiceToolError.invalidValue(argument: path, reason: "must be at least \(minimum)")
    }
    if let maximum, value > maximum {
      throw ServiceToolError.invalidValue(argument: path, reason: "must be at most \(maximum)")
    }
    if let exclusiveMinimum, value <= exclusiveMinimum {
      throw ServiceToolError.invalidValue(
        argument: path, reason: "must be greater than \(exclusiveMinimum)")
    }
    if let exclusiveMaximum, value >= exclusiveMaximum {
      throw ServiceToolError.invalidValue(
        argument: path, reason: "must be less than \(exclusiveMaximum)")
    }
    if let multipleOf, multipleOf != 0 {
      let quotient = value / multipleOf
      if abs(quotient.rounded() - quotient) > 1e-9 {
        throw ServiceToolError.invalidValue(
          argument: path, reason: "must be a multiple of \(multipleOf)")
      }
    }
  }

  private static func accepts(_ value: Value, schema: JSONSchema, path: String) -> Bool {
    do {
      try validate(value, against: schema, path: path)
      return true
    } catch {
      return false
    }
  }

  private static func equals(_ value: Value, _ expected: JSONValue) -> Bool {
    switch (value, expected) {
    case (.null, .null): return true
    case (.bool(let lhs), .bool(let rhs)): return lhs == rhs
    case (.int(let lhs), .int(let rhs)): return lhs == rhs
    case (.double(let lhs), .double(let rhs)): return lhs == rhs
    case (.int(let lhs), .double(let rhs)): return Double(lhs) == rhs
    case (.double(let lhs), .int(let rhs)): return lhs == Double(rhs)
    case (.string(let lhs), .string(let rhs)): return lhs == rhs
    case (.array(let lhs), .array(let rhs)):
      return lhs.count == rhs.count
        && zip(lhs, rhs).allSatisfy { equals($0.0, $0.1) }
    case (.object(let lhs), .object(let rhs)):
      return lhs.count == rhs.count
        && rhs.allSatisfy { key, value in
          lhs[key].map { equals($0, value) } ?? false
        }
    default:
      return false
    }
  }

  private static func matchesFormat(_ value: String, format: StringFormat) -> Bool {
    switch format {
    case .date:
      return matchesISODate(value)
    case .dateTime:
      return matchesISODateTime(value)
    case .email:
      return matchesEmail(value)
    case .uri:
      return URL(string: value)?.scheme != nil
    case .uuid:
      return UUID(uuidString: value) != nil
    default:
      return true
    }
  }

  private static func matchesEmail(_ value: String) -> Bool {
    let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
    guard
      !value.isEmpty,
      value.utf8.count <= 254,
      !value.unicodeScalars.contains(where: invalidCharacters.contains)
    else {
      return false
    }

    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let local = parts[0]
    let domain = parts[1]
    guard
      !local.isEmpty,
      local.utf8.count <= 64,
      !domain.isEmpty,
      !local.hasPrefix("."),
      !local.hasSuffix("."),
      !local.contains(".."),
      !domain.hasPrefix("."),
      !domain.hasSuffix("."),
      !domain.contains("..")
    else {
      return false
    }

    return domain.split(separator: ".").allSatisfy {
      !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-")
    }
  }

  /// Validates the date-time forms accepted by Rhythm without relying on mutable Foundation
  /// formatters, the process locale, or the current time zone.
  private static func matchesISODateTime(_ value: String) -> Bool {
    let parts = value.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
    let spaceParts =
      parts.count == 1
      ? value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
      : []
    let components = parts.count == 2 ? parts : spaceParts

    if components.count == 1 {
      return matchesISODate(String(components[0]))
    }
    guard components.count == 2, matchesISODate(String(components[0])) else {
      return false
    }
    return matchesISOTime(String(components[1]))
  }

  private static func matchesISODate(_ value: String) -> Bool {
    let fields = value.split(separator: "-", omittingEmptySubsequences: false)
    guard
      fields.count == 3,
      fields[0].count == 4,
      fields[1].count == 2,
      fields[2].count == 2,
      let year = decimal(fields[0]),
      let month = decimal(fields[1]),
      let day = decimal(fields[2]),
      (1...9999).contains(year),
      (1...12).contains(month)
    else {
      return false
    }

    let leapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    let monthLengths = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return (1...monthLengths[month - 1]).contains(day)
  }

  private static func matchesISOTime(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }

    let time: Substring
    let offset: Substring?
    if value.hasSuffix("Z") || value.hasSuffix("z") {
      time = value.dropLast()
      offset = nil
    } else if let signIndex = value.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) {
      time = value[..<signIndex]
      offset = value[signIndex...]
    } else {
      time = Substring(value)
      offset = nil
    }

    guard matchesClockTime(time) else { return false }
    guard let offset else { return true }
    return matchesUTCOffset(offset)
  }

  private static func matchesClockTime(_ value: Substring) -> Bool {
    let fields = value.split(separator: ":", omittingEmptySubsequences: false)
    guard fields.count == 2 || fields.count == 3 else { return false }
    guard
      fields[0].count == 2,
      fields[1].count == 2,
      let hour = decimal(fields[0]),
      let minute = decimal(fields[1]),
      (0...23).contains(hour),
      (0...59).contains(minute)
    else {
      return false
    }

    guard fields.count == 3 else { return true }
    let seconds = fields[2].split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard
      seconds.count == 1 || seconds.count == 2,
      seconds[0].count == 2,
      let second = decimal(seconds[0]),
      (0...59).contains(second)
    else {
      return false
    }
    return seconds.count == 1 || ((1...9).contains(seconds[1].count) && decimal(seconds[1]) != nil)
  }

  private static func matchesUTCOffset(_ value: Substring) -> Bool {
    guard value.first == "+" || value.first == "-" else { return false }
    let body = value.dropFirst()
    let fields = body.split(separator: ":", omittingEmptySubsequences: false)

    let hours: Substring
    let minutes: Substring
    if fields.count == 2 {
      hours = fields[0]
      minutes = fields[1]
    } else if fields.count == 1, body.count == 4 {
      hours = body.prefix(2)
      minutes = body.suffix(2)
    } else {
      return false
    }

    guard
      hours.count == 2,
      minutes.count == 2,
      let hour = decimal(hours),
      let minute = decimal(minutes)
    else {
      return false
    }
    return (0...14).contains(hour) && (0...59).contains(minute)
      && (hour < 14 || minute == 0)
  }

  private static func decimal(_ value: Substring) -> Int? {
    guard !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
    return Int(value)
  }

  private static func qualified(_ path: String, _ key: String) -> String {
    path == "arguments" ? key : "\(path).\(key)"
  }
}
