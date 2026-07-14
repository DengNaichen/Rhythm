import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteBinding {
  case text(String)
  case integer(Int64)
}

extension ThingsStore {
  func withDatabase<T>(at path: String, operation: (OpaquePointer) throws -> T) throws -> T {
    var database: OpaquePointer?
    let result = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK, let database else {
      defer { sqlite3_close(database) }
      throw ThingsDatabaseError.openFailed(database.map(Self.errorMessage(for:)) ?? "unknown error")
    }
    defer { sqlite3_close(database) }
    return try operation(database)
  }

  func prepareStatement(in database: OpaquePointer, sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard result == SQLITE_OK, let statement else {
      throw ThingsDatabaseError.prepareFailed(Self.errorMessage(for: database))
    }
    return statement
  }

  func bind(
    _ bindings: [SQLiteBinding], to statement: OpaquePointer, in database: OpaquePointer
  ) throws {
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch binding {
      case .text(let value):
        result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
      case .integer(let value):
        result = sqlite3_bind_int64(statement, index, value)
      }
      guard result == SQLITE_OK else {
        throw ThingsDatabaseError.bindFailed(Self.errorMessage(for: database))
      }
    }
  }

  func step(_ statement: OpaquePointer, in database: OpaquePointer) throws -> Bool {
    let result = sqlite3_step(statement)
    if result == SQLITE_ROW { return true }
    if result == SQLITE_DONE { return false }
    throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
  }

  static func stringValue(_ statement: OpaquePointer, column: Int32) -> String? {
    guard let textPointer = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: textPointer)
  }

  nonisolated private static func errorMessage(for database: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(database))
  }
}
