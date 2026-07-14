import EventKit
import Foundation

private let calendarServiceName = "Calendar"

extension ToolArgumentsDecoder {
  func calendarReferences() throws -> [EventKitCalendarReference]? {
    let ids = try nonEmptyStringArray("calendar_ids") ?? []
    let titles = try nonEmptyStringArray("list_names") ?? []
    if arguments["calendar_ids"] != nil, ids.isEmpty {
      throw ServiceToolError.invalidValue(
        argument: "calendar_ids",
        reason: "array must not be empty"
      )
    }
    if arguments["list_names"] != nil, titles.isEmpty {
      throw ServiceToolError.invalidValue(
        argument: "list_names",
        reason: "array must not be empty"
      )
    }
    guard !ids.isEmpty || !titles.isEmpty else { return nil }
    return ids.map(EventKitCalendarReference.id) + titles.map(EventKitCalendarReference.title)
  }

  func calendarReference() throws -> EventKitCalendarReference? {
    let id = arguments["calendar_id"] == nil ? nil : try requiredString("calendar_id")
    let title = arguments["list_name"] == nil ? nil : try requiredString("list_name")
    if id != nil, title != nil {
      throw ServiceToolError.invalidValue(
        argument: "calendar_id/list_name",
        reason: "provide one calendar reference, not both"
      )
    }
    if let id { return .id(id) }
    if let title { return .title(title) }
    return nil
  }

  func eventReference(calendar: Calendar) throws -> CalendarEventReference {
    let id = try requiredString("id")
    let occurrenceStart = try
      (arguments["occurrence_start"] == nil
      ? nil : requiredString("occurrence_start")).map {
        try DateRangeNormalizer.normalizeSingleDate(
          $0,
          argument: "occurrence_start",
          calendar: calendar
        )
      }
    let originalStartAt = try
      (arguments["original_start_at"] == nil
      ? nil : requiredString("original_start_at")).map {
        try DateRangeNormalizer.normalizeSingleDate(
          $0,
          argument: "original_start_at",
          calendar: calendar
        )
      }
    return CalendarEventReference(
      id: id,
      occurrenceStart: occurrenceStart,
      originalStartAt: originalStartAt
    )
  }

  func eventSpan() throws -> CalendarEventSpan {
    try enumValue(for: "span", default: CalendarEventSpan.thisEvent)
  }

  func url(_ key: String) throws -> URL? {
    guard arguments[key] != nil else { return nil }
    let string = try requiredString(key)
    guard let url = URL(string: string), url.scheme != nil else {
      throw ServiceToolError.invalidURL(argument: key, value: string)
    }
    return url
  }

  func date(_ key: String, calendar: Calendar) throws -> Date {
    try DateRangeNormalizer.normalizeSingleDate(
      requiredString(key),
      argument: key,
      calendar: calendar
    )
  }

  func optionalDate(_ key: String, calendar: Calendar) throws -> Date? {
    guard arguments[key] != nil else { return nil }
    let value = try requiredString(key)
    return try DateRangeNormalizer.normalizeSingleDate(
      value,
      argument: key,
      calendar: calendar
    )
  }

  func timeZoneIdentifier(_ key: String) throws -> String? {
    guard arguments[key] != nil else { return nil }
    let identifier = try requiredString(key)
    guard TimeZone(identifier: identifier) != nil else {
      throw ServiceToolError.invalidValue(
        argument: key,
        reason: "expected an IANA time zone identifier"
      )
    }
    return identifier
  }

  func notes(_ key: String) throws -> String? {
    guard let value = arguments[key] else { return nil }
    guard let string = value.stringValue else {
      throw ServiceToolError.invalidType(argument: key, expected: "string")
    }
    return string
  }

  func alarms(_ key: String, calendar: Calendar) throws -> [CalendarAlarmInput]? {
    guard let values = try optionalArray(key) else { return nil }
    return try values.enumerated().map { index, value in
      guard let object = value.objectValue else {
        throw ServiceToolError.invalidType(argument: "\(key)[\(index)]", expected: "object")
      }
      return try Self.alarm(
        ToolArgumentsDecoder(arguments: object),
        path: "\(key)[\(index)]",
        calendar: calendar
      )
    }
  }

  func recurrence(_ key: String, calendar: Calendar) throws -> CalendarRecurrenceRule? {
    guard let value = arguments[key] else { return nil }
    guard let object = value.objectValue else {
      throw ServiceToolError.invalidType(argument: key, expected: "object")
    }

    let decoder = ToolArgumentsDecoder(arguments: object)
    let frequency = try decoder.enumValue(for: "frequency") as CalendarRecurrenceFrequency
    let interval = try decoder.optionalInt("interval") ?? 1
    guard (1...CalendarRecurrenceRule.maximumInterval).contains(interval) else {
      throw ServiceToolError.invalidValue(
        argument: "\(key).interval",
        reason: "must be between 1 and \(CalendarRecurrenceRule.maximumInterval)"
      )
    }

    let endAt = try
      (decoder.arguments["end_at"] == nil
      ? nil : decoder.requiredString("end_at")).map {
        try DateRangeNormalizer.normalizeSingleDate(
          $0,
          argument: "\(key).end_at",
          calendar: calendar
        )
      }
    let occurrenceCount = try decoder.optionalInt("occurrence_count")
    if endAt != nil, occurrenceCount != nil {
      throw ServiceToolError.invalidValue(
        argument: key,
        reason: "end_at and occurrence_count are mutually exclusive"
      )
    }

    let recurrenceEnd: CalendarRecurrenceEnd?
    if let endAt {
      recurrenceEnd = .endDate(endAt)
    } else if let occurrenceCount {
      guard occurrenceCount > 0 else {
        throw ServiceToolError.invalidValue(
          argument: "\(key).occurrence_count",
          reason: "must be positive"
        )
      }
      recurrenceEnd = .occurrenceCount(occurrenceCount)
    } else {
      recurrenceEnd = nil
    }

    return CalendarRecurrenceRule(
      frequency: frequency,
      interval: interval,
      daysOfTheWeek: try decoder.recurrenceWeekdays("by_day", path: key),
      daysOfTheMonth: try decoder.integerArray(
        "by_month_day", path: key, range: -31...31, excludesZero: true),
      monthsOfTheYear: try decoder.integerArray(
        "by_month", path: key, range: 1...12, excludesZero: false),
      weeksOfTheYear: try decoder.integerArray(
        "by_week_no", path: key, range: -53...53, excludesZero: true),
      daysOfTheYear: try decoder.integerArray(
        "by_year_day", path: key, range: -366...366, excludesZero: true),
      setPositions: try decoder.integerArray(
        "by_set_pos", path: key, range: -366...366, excludesZero: true),
      end: recurrenceEnd
    )
  }

  func stringUpdate(
    _ key: String,
    preserveWhitespace: Bool = false
  ) throws -> CalendarFieldUpdate<String> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let string = value.stringValue else {
      throw ServiceToolError.invalidType(argument: key, expected: "string or null")
    }
    if preserveWhitespace { return string.isEmpty ? .clear : .set(string) }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .clear : .set(trimmed)
  }

  func urlUpdate(_ key: String) throws -> CalendarFieldUpdate<URL> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let parsed = try url(key) else { return .unchanged }
    return .set(parsed)
  }

  func alarmValuesUpdate(
    _ key: String,
    calendar: Calendar
  ) throws -> [CalendarAlarmInput]? {
    guard let value = arguments[key] else { return nil }
    if value.isNull { return [] }
    return try alarms(key, calendar: calendar)!
  }

  func recurrenceValuesUpdate(
    _ key: String,
    calendar: Calendar
  ) throws -> [CalendarRecurrenceRule]? {
    guard let value = arguments[key] else { return nil }
    if value.isNull { return [] }
    guard let rule = try recurrence(key, calendar: calendar) else { return nil }
    return [rule]
  }

  func timeZoneUpdate(_ key: String) throws -> CalendarFieldUpdate<String> {
    guard let value = arguments[key] else { return .unchanged }
    if value.isNull { return .clear }
    guard let identifier = try timeZoneIdentifier(key) else { return .unchanged }
    return .set(identifier)
  }

  private static func alarm(
    _ decoder: ToolArgumentsDecoder,
    path: String,
    calendar: Calendar
  ) throws -> CalendarAlarmInput {
    let kind = try decoder.enumValue(for: "type") as CalendarAlarmKind
    let emailAddress = try decoder.optionalString("email_address")
    let relativeKeys = ["minutes"]
    let absoluteKeys = ["at"]
    let proximityKeys = ["proximity", "location_title", "latitude", "longitude", "radius"]

    switch kind {
    case .relative:
      try decoder.rejectPresent(absoluteKeys + proximityKeys, path: path, kind: kind.rawValue)
      guard let minutes = try decoder.optionalInt("minutes"),
        (0...CalendarAlarmInput.maximumRelativeMinutes).contains(minutes)
      else {
        throw ServiceToolError.invalidValue(
          argument: "\(path).minutes",
          reason:
            "an integer from 0 through \(CalendarAlarmInput.maximumRelativeMinutes) is required for a relative alarm"
        )
      }
      return .relative(minutes: minutes, emailAddress: emailAddress)

    case .absolute:
      try decoder.rejectPresent(relativeKeys + proximityKeys, path: path, kind: kind.rawValue)
      let raw = try decoder.requiredString("at")
      let date = try DateRangeNormalizer.normalizeSingleDate(
        raw,
        argument: "\(path).at",
        calendar: calendar
      )
      return .absolute(at: date, emailAddress: emailAddress)

    case .proximity:
      try decoder.rejectPresent(relativeKeys + absoluteKeys, path: path, kind: kind.rawValue)
      guard let latitude = try decoder.optionalDouble("latitude"), (-90...90).contains(latitude)
      else {
        throw ServiceToolError.invalidValue(
          argument: "\(path).latitude",
          reason: "a value from -90 through 90 is required"
        )
      }
      guard let longitude = try decoder.optionalDouble("longitude"),
        (-180...180).contains(longitude)
      else {
        throw ServiceToolError.invalidValue(
          argument: "\(path).longitude",
          reason: "a value from -180 through 180 is required"
        )
      }
      let radius = try decoder.optionalDouble("radius") ?? 200
      guard radius > 0 else {
        throw ServiceToolError.invalidValue(
          argument: "\(path).radius",
          reason: "must be greater than zero"
        )
      }
      return .proximity(
        proximity: try decoder.enumValue(for: "proximity", default: AlarmProximityKind.enter),
        locationTitle: try decoder.requiredString("location_title"),
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        emailAddress: emailAddress
      )
    }
  }

  private func rejectPresent(_ keys: [String], path: String, kind: String) throws {
    if let key = keys.first(where: { arguments[$0] != nil }) {
      throw ServiceToolError.invalidValue(
        argument: "\(path).\(key)",
        reason: "is not valid for a \(kind) alarm"
      )
    }
  }

  private func integerArray(
    _ key: String,
    path: String,
    range: ClosedRange<Int>,
    excludesZero: Bool
  ) throws -> [Int] {
    guard let values = try optionalArray(key) else { return [] }
    return try values.enumerated().map { index, value in
      guard let integer = value.intValue else {
        throw ServiceToolError.invalidType(
          argument: "\(path).\(key)[\(index)]",
          expected: "integer"
        )
      }
      guard range.contains(integer), !excludesZero || integer != 0 else {
        throw ServiceToolError.invalidValue(
          argument: "\(path).\(key)[\(index)]",
          reason: "value must be in \(range)\(excludesZero ? " excluding zero" : "")"
        )
      }
      return integer
    }
  }

  private func recurrenceWeekdays(
    _ key: String,
    path: String
  ) throws -> [CalendarRecurrenceWeekday] {
    let values = try nonEmptyStringArray(key) ?? []
    return try values.enumerated().map { index, token in
      try Self.recurrenceWeekday(token, argument: "\(path).\(key)[\(index)]")
    }
  }

  private static func recurrenceWeekday(
    _ input: String,
    argument: String
  ) throws -> CalendarRecurrenceWeekday {
    let value = input.uppercased()
    guard value.count >= 2 else {
      throw invalidWeekday(argument: argument, value: input)
    }
    let suffix = String(value.suffix(2))
    let weekdays: [String: CalendarWeekday] = [
      "SU": .sunday,
      "MO": .monday,
      "TU": .tuesday,
      "WE": .wednesday,
      "TH": .thursday,
      "FR": .friday,
      "SA": .saturday,
    ]
    guard let day = weekdays[suffix] else {
      throw invalidWeekday(argument: argument, value: input)
    }

    let prefix = String(value.dropLast(2))
    let weekNumber: Int
    if prefix.isEmpty {
      weekNumber = 0
    } else if let parsed = Int(prefix), parsed != 0, (-53...53).contains(parsed) {
      weekNumber = parsed
    } else {
      throw invalidWeekday(argument: argument, value: input)
    }
    return CalendarRecurrenceWeekday(day: day, weekNumber: weekNumber)
  }

  private static func invalidWeekday(argument: String, value: String) -> ServiceToolError {
    .invalidValue(
      argument: argument,
      reason: "'\(value)' is not an RFC 5545 weekday such as MO, 1MO, or -1SU"
    )
  }

  private func nonEmptyStringArray(_ key: String) throws -> [String]? {
    guard let values = try optionalArray(key) else { return nil }
    return try values.enumerated().map { index, value in
      guard let string = value.stringValue else {
        throw ServiceToolError.invalidType(argument: "\(key)[\(index)]", expected: "string")
      }
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw ServiceToolError.invalidValue(
          argument: "\(key)[\(index)]",
          reason: "value must not be empty"
        )
      }
      return trimmed
    }
  }
}

@MainActor
func requireCalendarAuthorization(_ runtime: EventKitRuntime) throws {
  guard runtime.eventAuthorizationStatus() == .fullAccess else {
    throw ServiceToolError.unauthorized(service: calendarServiceName)
  }
}
