import Foundation

extension ThingsStore {
  func appendDateFilter(
    column: String,
    exact: String?,
    from: String?,
    to: String?,
    clauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) throws {
    if let exact {
      clauses.append("\(column) = ?")
      bindings.append(.integer(Int64(try thingsDate(forISODate: exact))))
      return
    }
    if let from {
      clauses.append("\(column) >= ?")
      bindings.append(.integer(Int64(try thingsDate(forISODate: from))))
    }
    if let to {
      clauses.append("\(column) <= ?")
      bindings.append(.integer(Int64(try thingsDate(forISODate: to))))
    }
  }

  func appendReminderFilter(
    dateColumn: String,
    timeColumn: String,
    from: String?,
    to: String?,
    clauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) throws {
    let expression = Self.reminderDateTimeExpression(
      dateColumn: dateColumn,
      timeColumn: timeColumn
    )
    if let from {
      clauses.append("\(expression) >= ?")
      bindings.append(.text(try normalizedReminderDateTime(from, upperBound: false)))
    }
    if let to {
      clauses.append("\(expression) <= ?")
      bindings.append(.text(try normalizedReminderDateTime(to, upperBound: true)))
    }
  }

  func appendTimestampFilter(
    column: String,
    from: String?,
    to: String?,
    clauses: inout [String],
    bindings: inout [SQLiteBinding]
  ) throws {
    let expression = "datetime(\(column), 'unixepoch', 'localtime')"
    if let from {
      clauses.append("\(expression) >= ?")
      bindings.append(.text(try normalizedTimestampBound(from, upper: false)))
    }
    if let to {
      clauses.append("\(expression) <= ?")
      bindings.append(.text(try normalizedTimestampBound(to, upper: true)))
    }
  }

  private func normalizedReminderDateTime(_ value: String, upperBound: Bool) throws -> String {
    guard
      let date = ThingsDateTimeInput.reminder(
        value,
        upperBound: upperBound,
        calendar: calendar
      )
    else {
      throw ThingsServiceError.invalidValue(
        "reminder date-time",
        reason: "expected local YYYY-MM-DDTHH:MM or an RFC 3339 timestamp"
      )
    }
    return ThingsDateTimeInput.localTimestamp(date, calendar: calendar, separator: "T")
  }

  private func normalizedTimestampBound(_ value: String, upper: Bool) throws -> String {
    guard
      let date = ThingsDateTimeInput.timestamp(
        value,
        upperBound: upper,
        calendar: calendar
      )
    else {
      throw ThingsServiceError.invalidValue(
        "date-time",
        reason:
          "expected local YYYY-MM-DD[THH:MM[:SS]] or an RFC 3339 timestamp"
      )
    }
    return ThingsDateTimeInput.localTimestamp(date, calendar: calendar, separator: " ")
  }

  private func thingsDate(forISODate value: String) throws -> Int {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
      throw ThingsServiceError.invalidDate(value)
    }
    return Self.thingsDate(for: date, calendar: formatter.calendar)
  }
}
