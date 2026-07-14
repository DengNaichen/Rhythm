import Foundation

nonisolated enum CalendarAuthorizationState: Equatable, Sendable {
  case notDetermined
  case granted
  case denied
}

nonisolated enum CalendarEventStatusFilter: String, CaseIterable, Sendable {
  case none
  case tentative
  case confirmed
  case canceled
}

nonisolated enum CalendarAvailabilityFilter: String, CaseIterable, Sendable {
  case busy
  case free
  case tentative
  case unavailable
}

nonisolated enum CalendarEventSpan: String, CaseIterable, Sendable {
  case thisEvent = "this_event"
  case futureEvents = "future_events"
}

nonisolated enum EventKitCalendarReference: Equatable, Sendable {
  case id(String)
  case title(String)

  var value: String {
    switch self {
    case .id(let value), .title(let value):
      return value
    }
  }

  var kind: String {
    switch self {
    case .id:
      return "id"
    case .title:
      return "title"
    }
  }
}

nonisolated struct CalendarEventReference: Equatable, Sendable {
  let id: String
  let occurrenceStart: Date?
  let originalStartAt: Date?

  init(
    id: String,
    occurrenceStart: Date? = nil,
    originalStartAt: Date? = nil
  ) {
    self.id = id
    self.occurrenceStart = occurrenceStart
    self.originalStartAt = originalStartAt
  }
}

nonisolated struct EventKitListRecord: Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  let source: String
  let color: String
  let isEditable: Bool
  let isSubscribed: Bool
}

nonisolated enum CalendarFieldUpdate<Value>: Equatable, Sendable
where Value: Equatable & Sendable {
  case unchanged
  case set(Value)
  case clear
}

nonisolated enum CalendarEventRuntimeError: Error, Equatable, LocalizedError, Sendable {
  case emptyCalendarReference(kind: String)
  case calendarNotFound(EventKitCalendarReference)
  case ambiguousCalendarTitle(title: String, matchingIDs: [String])
  case calendarNotWritable(id: String, title: String)
  case defaultCalendarUnavailable
  case eventNotFound(CalendarEventReference)
  case eventNotWritable(id: String, calendarTitle: String)
  case invalidInput(argument: String, reason: String)

  var errorDescription: String? {
    switch self {
    case .emptyCalendarReference(let kind):
      return "Calendar \(kind) must not be empty."
    case .calendarNotFound(let reference):
      return "No calendar matches \(reference.kind) '\(reference.value)'."
    case .ambiguousCalendarTitle(let title, let matchingIDs):
      return
        "Calendar title '\(title)' is ambiguous; matching IDs: \(matchingIDs.joined(separator: ", "))."
    case .calendarNotWritable(let id, let title):
      return "Calendar '\(title)' (\(id)) does not allow modifications."
    case .defaultCalendarUnavailable:
      return "No writable default event calendar is available."
    case .eventNotFound(let reference):
      if reference.occurrenceStart != nil || reference.originalStartAt != nil {
        let actual = reference.occurrenceStart.map(EventKitDateFormatting.iso8601String(from:))
        let original = reference.originalStartAt.map(EventKitDateFormatting.iso8601String(from:))
        let details = [
          actual.map { "start \($0)" },
          original.map { "original start \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
        return "Event '\(reference.id)' occurrence (\(details)) was not found."
      }
      return "Event '\(reference.id)' was not found."
    case .eventNotWritable(let id, let calendarTitle):
      return "Event '\(id)' in calendar '\(calendarTitle)' does not allow modifications."
    case .invalidInput(let argument, let reason):
      return "Invalid \(argument): \(reason)"
    }
  }
}

nonisolated enum EventKitDateFormatting {
  static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func localDateString(
    from date: Date,
    calendar: Calendar = .eventKitGregorian
  ) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }
}

extension Calendar {
  nonisolated static var eventKitGregorian: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .current
    return calendar
  }
}
