import Foundation

nonisolated extension ThingsURLBuilder {
  func append(
    _ patch: ThingsPatch<String>,
    key: String,
    to queryItems: inout [(String, String)]
  ) {
    switch patch {
    case .unchanged:
      break
    case .clear:
      queryItems.append((key, ""))
    case .value(let value):
      queryItems.append((key, value))
    }
  }

  func append(
    _ patch: ThingsPatch<[String]>,
    key: String,
    separator: String,
    to queryItems: inout [(String, String)]
  ) {
    switch patch {
    case .unchanged:
      break
    case .clear:
      queryItems.append((key, ""))
    case .value(let values):
      queryItems.append((key, values.joined(separator: separator)))
    }
  }

  func appendDestination(
    _ patch: ThingsPatch<String>,
    to queryItems: inout [(String, String)]
  ) {
    switch patch {
    case .unchanged:
      break
    case .clear:
      queryItems.append(("list", ""))
    case .value(let value):
      appendReference(value, idKey: "list-id", titleKey: "list", to: &queryItems)
    }
  }

  func appendHeading(
    _ patch: ThingsPatch<String>,
    to queryItems: inout [(String, String)]
  ) {
    switch patch {
    case .unchanged:
      break
    case .clear:
      queryItems.append(("heading", ""))
    case .value(let value):
      appendReference(value, idKey: "heading-id", titleKey: "heading", to: &queryItems)
    }
  }

  func appendArea(
    _ patch: ThingsPatch<String>,
    to queryItems: inout [(String, String)]
  ) {
    switch patch {
    case .unchanged:
      break
    case .clear:
      queryItems.append(("area", ""))
    case .value(let value):
      appendReference(value, idKey: "area-id", titleKey: "area", to: &queryItems)
    }
  }

  func appendReference(
    _ value: String,
    idKey: String,
    titleKey: String,
    to queryItems: inout [(String, String)]
  ) {
    let parsed = ThingsEntityID.parse(value)
    if parsed.kind != nil || Self.looksLikeThingsID(parsed.rawID) {
      queryItems.append((idKey, parsed.rawID))
    } else {
      queryItems.append((titleKey, value))
    }
  }

  func appendStatus(
    _ status: ThingsItemStatus?,
    to queryItems: inout [(String, String)]
  ) {
    switch status {
    case .completed:
      queryItems.append(("completed", "true"))
    case .canceled:
      queryItems.append(("canceled", "true"))
    case .incomplete:
      queryItems.append(("completed", "false"))
      queryItems.append(("canceled", "false"))
    case .all, nil:
      break
    }
  }

  func appendCallbacks(
    _ callbacks: ThingsURLCallbacks?,
    to queryItems: inout [(String, String)]
  ) {
    guard let callbacks else { return }
    if let success = callbacks.success {
      queryItems.append(("x-success", success.absoluteString))
    }
    if let error = callbacks.error {
      queryItems.append(("x-error", error.absoluteString))
    }
    if let cancel = callbacks.cancel {
      queryItems.append(("x-cancel", cancel.absoluteString))
    }
  }

  func buildURL(command: String, queryItems: [(String, String)]) throws -> URL {
    for (key, value) in queryItems where key != "data" {
      let maximum = ["notes", "prepend-notes", "append-notes"].contains(key) ? 10_000 : 4_000
      guard value.count <= maximum else {
        throw ThingsServiceError.invalidValue(
          key, reason: "maximum unencoded length is \(maximum) characters")
      }
    }

    let encodedQuery =
      queryItems
      .map { key, value in
        "\(key)=\(Self.encode(value))"
      }
      .joined(separator: "&")

    let urlString =
      encodedQuery.isEmpty
      ? "things:///\(command)"
      : "things:///\(command)?\(encodedQuery)"
    guard let url = URL(string: urlString) else {
      throw ThingsURLBuilderError.invalidURL
    }
    return url
  }

  static func looksLikeThingsID(_ value: String) -> Bool {
    guard value.count >= 20 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.unicodeScalars.allSatisfy(allowed.contains)
  }

  func validateLineSeparatedValues(
    _ patch: ThingsPatch<[String]>,
    key: String,
    maximumCount: Int
  ) throws {
    guard case .value(let values) = patch else { return }
    try validateLineSeparatedValues(values, key: key, maximumCount: maximumCount)
  }

  func validateDelimitedValues(
    _ patch: ThingsPatch<[String]>,
    key: String,
    delimiter: String
  ) throws {
    guard case .value(let values) = patch else { return }
    try validateDelimitedValues(values, key: key, delimiter: delimiter)
  }

  func validateDelimitedValues(
    _ values: [String]?,
    key: String,
    delimiter: String
  ) throws {
    for (index, value) in (values ?? []).enumerated() {
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      guard !value.contains(delimiter) else {
        throw ThingsServiceError.invalidValue(
          "\(key)[\(index)]", reason: "the value contains the Things '\(delimiter)' delimiter")
      }
    }
  }

  func validateLineSeparatedValues(
    _ values: [String]?,
    key: String,
    maximumCount: Int
  ) throws {
    guard let values else { return }
    guard values.count <= maximumCount else {
      throw ThingsServiceError.invalidValue(key, reason: "maximum item count is \(maximumCount)")
    }
    for (index, value) in values.enumerated() {
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ThingsServiceError.invalidValue("\(key)[\(index)]", reason: "value must not be empty")
      }
      guard value.rangeOfCharacter(from: .newlines) == nil else {
        throw ThingsServiceError.invalidValue(
          "\(key)[\(index)]", reason: "embedded newlines would create additional items")
      }
    }
  }

  func validateStringLength(
    _ value: String?,
    key: String,
    maximum: Int = 4_000
  ) throws {
    guard let value, value.count > maximum else { return }
    throw ThingsServiceError.invalidValue(
      key, reason: "maximum unencoded length is \(maximum) characters")
  }

  private static func encode(_ value: String) -> String {
    let allowedCharacters = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-._~")
    )
    return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
  }
}
