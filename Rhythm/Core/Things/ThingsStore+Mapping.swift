import Foundation
import SQLite3

extension ThingsStore {
  static func databasePage<Item: Encodable>(
    _ values: [Item],
    request: ThingsPageRequest
  ) -> ThingsPage<Item> {
    let hasMore = values.count > request.limit
    let items = hasMore ? Array(values.prefix(request.limit)) : values
    let cursor = hasMore ? String(request.offset + request.limit) : nil
    return ThingsPage(items: items, nextCursor: cursor)
  }

  static func reference(kind: ThingsEntityKind, id: String?, title: String?)
    -> ThingsReference?
  {
    reference(prefixKind: kind, id: id, title: title)
  }

  static func itemStatus(from rawValue: Int32) -> ThingsItemStatus {
    switch rawValue {
    case 0: return .incomplete
    case 3: return .completed
    default: return .canceled
    }
  }

  static func showURL(_ rawID: String) -> String {
    "things:///show?id=\(rawID)"
  }

  static func looksLikeThingsID(_ value: String) -> Bool {
    guard value.count >= 20 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.unicodeScalars.allSatisfy(allowed.contains)
  }

  static func likePattern(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
    return "%\(escaped)%"
  }

  static func reminderDateTime(date: String?, time: String?) -> String? {
    guard let date, let time else { return nil }
    return "\(date)T\(time)"
  }

  static func repeatingMetadata(
    from statement: OpaquePointer,
    startingAt column: Int32,
    kind: ThingsEntityKind
  ) -> ThingsRepeatingMetadata? {
    let isTemplate = sqlite3_column_int(statement, column + 2) != 0
    let template = reference(
      kind: kind,
      id: stringValue(statement, column: column),
      title: stringValue(statement, column: column + 1)
    )
    let ruleDataBase64 = blobBase64(statement, column: column + 9)
    guard isTemplate || template != nil || ruleDataBase64 != nil else { return nil }

    return ThingsRepeatingMetadata(
      isTemplate: isTemplate,
      template: template,
      paused: optionalBool(statement, column: column + 3),
      nextOccurrence: stringValue(statement, column: column + 7),
      instanceCreationStart: stringValue(statement, column: column + 4),
      instanceCount: optionalInt(statement, column: column + 5),
      afterCompletionReferenceAt: stringValue(statement, column: column + 6),
      deadlineOffsetDays: optionalInt(statement, column: column + 8),
      ruleDataBase64: ruleDataBase64
    )
  }

  private static func reference(prefixKind: ThingsEntityKind?, id: String?, title: String?)
    -> ThingsReference?
  {
    guard let id, let title else { return nil }
    return ThingsReference(
      id: prefixKind.map { ThingsEntityID.make($0, rawID: id) } ?? id,
      title: title
    )
  }

  private static func optionalBool(_ statement: OpaquePointer, column: Int32) -> Bool? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return sqlite3_column_int(statement, column) != 0
  }

  private static func optionalInt(_ statement: OpaquePointer, column: Int32) -> Int? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, column))
  }

  private static func blobBase64(_ statement: OpaquePointer, column: Int32) -> String? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    let byteCount = Int(sqlite3_column_bytes(statement, column))
    guard byteCount > 0 else { return "" }
    guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
    return Data(bytes: bytes, count: byteCount).base64EncodedString()
  }
}
