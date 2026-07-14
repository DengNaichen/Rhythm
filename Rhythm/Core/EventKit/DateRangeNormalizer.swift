import Foundation

nonisolated struct DateRange: Equatable, Sendable {
  let from: Date
  let to: Date
}

nonisolated struct OptionalDateRange: Equatable, Sendable {
  let from: Date?
  let to: Date?
}

nonisolated enum DateRangeNormalizer {
  static func normalizeCalendarRange(
    from rawFrom: String?,
    to rawTo: String?,
    now: () -> Date = { Date() },
    calendar: Calendar = .eventKitGregorian
  ) throws -> DateRange {
    let parsedFrom = try parse(rawFrom, argument: "from", calendar: calendar)
    let parsedTo = try parse(rawTo, argument: "to", calendar: calendar)

    var fromDate = parsedFrom?.date ?? now()
    var toDate =
      parsedTo?.date
      ?? calendar.date(byAdding: .weekOfYear, value: 1, to: fromDate)
      ?? fromDate

    var fromIsDateOnly = parsedFrom?.isDateOnly ?? false
    let toIsDateOnly = parsedTo?.isDateOnly ?? false

    if parsedFrom == nil, let parsedTo, parsedTo.isDateOnly {
      fromDate = parsedTo.date
      fromIsDateOnly = true
    }

    fromDate = calendar.normalizedStartDate(from: fromDate, isDateOnly: fromIsDateOnly)

    if toIsDateOnly {
      toDate = calendar.normalizedEndDate(from: toDate, isDateOnly: true)
    } else if parsedTo == nil {
      if fromIsDateOnly {
        toDate = calendar.normalizedEndDate(from: fromDate, isDateOnly: true)
      } else {
        toDate = calendar.date(byAdding: .weekOfYear, value: 1, to: fromDate) ?? toDate
      }
    }

    guard toDate >= fromDate else {
      throw ServiceToolError.invalidValue(
        argument: "to",
        reason: "'to' must be later than or equal to 'from'"
      )
    }

    return DateRange(from: fromDate, to: toDate)
  }

  static func normalizeSingleDate(
    _ rawValue: String,
    argument: String,
    calendar: Calendar = .eventKitGregorian
  ) throws -> Date {
    let parsed = try parse(rawValue, argument: argument, calendar: calendar)
    guard let parsed else {
      throw ServiceToolError.missingRequiredArgument(argument)
    }

    return calendar.normalizedStartDate(from: parsed.date, isDateOnly: parsed.isDateOnly)
  }

  static func normalizeOptionalRange(
    from rawFrom: String?,
    to rawTo: String?,
    calendar: Calendar = .eventKitGregorian
  ) throws -> OptionalDateRange {
    let parsedFrom = try parse(rawFrom, argument: "from", calendar: calendar)
    let parsedTo = try parse(rawTo, argument: "to", calendar: calendar)

    let fromDate = parsedFrom.map {
      calendar.normalizedStartDate(from: $0.date, isDateOnly: $0.isDateOnly)
    }
    let toDate = parsedTo.map {
      calendar.normalizedEndDate(from: $0.date, isDateOnly: $0.isDateOnly)
    }

    if let fromDate, let toDate, toDate < fromDate {
      throw ServiceToolError.invalidValue(
        argument: "to",
        reason: "'to' must be later than or equal to 'from'"
      )
    }

    return OptionalDateRange(from: fromDate, to: toDate)
  }

  static func parse(
    _ rawValue: String?,
    argument: String
  ) throws -> (date: Date, isDateOnly: Bool)? {
    try parse(rawValue, argument: argument, calendar: .eventKitGregorian)
  }

  static func parse(
    _ rawValue: String?,
    argument: String,
    calendar: Calendar
  ) throws -> (date: Date, isDateOnly: Bool)? {
    guard let rawValue else {
      return nil
    }

    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    if let date = parseDateOnly(trimmed, calendar: calendar) {
      return (date, true)
    }

    let date: Date?
    if hasExplicitTimeZone(trimmed) {
      date = ISO8601DateFormatter.lenientDate(fromISO8601String: trimmed)
    } else {
      date = parseLocalDateTime(trimmed, calendar: calendar)
    }

    guard let date else {
      throw ServiceToolError.invalidDate(argument: argument, value: trimmed)
    }
    return (date, false)
  }

  private static func parseDateOnly(_ value: String, calendar: Calendar) -> Date? {
    guard value.count == 10 else { return nil }
    let characters = Array(value)
    guard characters[4] == "-", characters[7] == "-" else { return nil }
    guard
      let year = Int(String(characters[0...3])),
      let month = Int(String(characters[5...6])),
      let day = Int(String(characters[8...9]))
    else {
      return nil
    }

    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = 0
    components.minute = 0
    components.second = 0

    guard let date = calendar.date(from: components) else { return nil }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    guard resolved.year == year, resolved.month == month, resolved.day == day else {
      return nil
    }
    return date
  }

  private static func hasExplicitTimeZone(_ value: String) -> Bool {
    value.range(
      of: #"([Zz]|[+-]\d{2}(:?\d{2})?)$"#,
      options: .regularExpression
    ) != nil
  }

  private static func parseLocalDateTime(_ value: String, calendar: Calendar) -> Date? {
    let format: String
    if value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"#, options: .regularExpression)
      != nil
    {
      format = "yyyy-MM-dd'T'HH:mm"
    } else if value.range(
      of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#,
      options: .regularExpression
    ) != nil {
      format = "yyyy-MM-dd HH:mm"
    } else if value.range(
      of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#,
      options: .regularExpression
    ) != nil {
      format = "yyyy-MM-dd'T'HH:mm:ss"
    } else if value.range(
      of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#,
      options: .regularExpression
    ) != nil {
      format = "yyyy-MM-dd HH:mm:ss"
    } else if value.range(
      of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{1,9}$"#,
      options: .regularExpression
    ) != nil {
      format = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSS"
    } else if value.range(
      of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,9}$"#,
      options: .regularExpression
    ) != nil {
      format = "yyyy-MM-dd HH:mm:ss.SSSSSSSSS"
    } else {
      return nil
    }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter.date(from: value)
  }
}
