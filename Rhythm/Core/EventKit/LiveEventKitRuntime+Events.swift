import EventKit
import Foundation

extension LiveEventKitRuntime {
  func fetchEvents(_ input: CalendarEventsFetchInput) throws -> [CalendarEventRecord] {
    guard input.range.to >= input.range.from else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "to",
        reason: "end must be later than or equal to start"
      )
    }
    if input.range.to == input.range.from {
      return []
    }
    guard
      let maximumEnd = calendar.date(byAdding: .year, value: 4, to: input.range.from),
      input.range.to <= maximumEnd
    else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "to",
        reason: "EventKit event queries cannot span more than four years"
      )
    }

    let calendars = try resolveCalendars(input.calendars)
    if calendars?.isEmpty == true {
      return []
    }

    let predicate = eventStore.predicateForEvents(
      withStart: input.range.from,
      end: input.range.to,
      calendars: calendars
    )
    var records = eventStore.events(matching: predicate).map(Self.makeEventRecord(from:))

    if !input.includeAllDay {
      records.removeAll(where: \.isAllDay)
    }
    if let query = input.query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !query.isEmpty
    {
      records = records.filter { record in
        record.title.lowercased().contains(query)
          || (record.location?.lowercased().contains(query) ?? false)
          || (record.notes?.lowercased().contains(query) ?? false)
      }
    }
    if let status = input.status {
      records.removeAll { $0.status != status.rawValue }
    }
    if let availability = input.availability {
      records.removeAll { $0.availability != availability.rawValue }
    }
    if let hasAlarms = input.hasAlarms {
      records.removeAll { $0.hasAlarms != hasAlarms }
    }
    if let isRecurring = input.isRecurring {
      records.removeAll { $0.isRecurring != isRecurring }
    }

    return records.sorted {
      if $0.startAt == $1.startAt {
        if $0.id == $1.id {
          return ($0.occurrenceStart ?? .distantPast) < ($1.occurrenceStart ?? .distantPast)
        }
        return $0.id < $1.id
      }
      return $0.startAt < $1.startAt
    }
  }

  func event(_ reference: CalendarEventReference) throws -> CalendarEventRecord {
    Self.makeEventRecord(from: try resolveEvent(reference))
  }

  func createEvent(_ input: CalendarEventCreateInput) throws -> CalendarEventRecord {
    let event = EKEvent(eventStore: eventStore)
    let title = try validatedTitle(input.title)
    let range = try normalizedRange(
      startAt: input.startAt,
      endAt: input.endAt,
      isAllDay: input.isAllDay
    )
    let destination = try resolveWritableCalendar(input.calendar)

    event.title = title
    event.startDate = range.startAt
    event.endDate = range.endAt
    event.isAllDay = input.isAllDay
    event.calendar = destination
    event.location = input.location
    event.notes = input.notes
    event.url = input.url
    event.timeZone = try resolveTimeZone(input.timeZoneIdentifier, argument: "time_zone")

    if let availability = input.availability {
      try validateAvailability(availability, for: destination)
      event.availability = EKEventAvailability(availability)
    }

    event.alarms = try input.alarms.map(makeEventAlarm(from:))
    try validateRecurrenceEndDates(input.recurrenceRules, eventStart: range.startAt)
    event.recurrenceRules = try input.recurrenceRules.map(makeRecurrenceRule(from:))

    try eventStore.save(event, span: .thisEvent)
    return Self.makeEventRecord(from: event)
  }

  func updateEvent(
    _ reference: CalendarEventReference,
    input: CalendarEventUpdateInput,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord {
    let event = try resolveEvent(reference)
    try requireWritable(event, reference: reference)

    if let title = input.title {
      event.title = try validatedTitle(title)
    }
    if let destinationReference = input.calendar {
      event.calendar = try resolveWritableCalendar(destinationReference)
    }

    try apply(input.location, to: &event.location)
    try apply(input.notes, to: &event.notes)
    try apply(input.url, to: &event.url)
    try applyTimeZone(input.timeZoneIdentifier, to: event)

    let isAllDay = input.isAllDay ?? event.isAllDay
    let range = try normalizedRange(
      startAt: input.startAt ?? event.startDate,
      endAt: input.endAt ?? event.endDate,
      isAllDay: isAllDay
    )
    event.startDate = range.startAt
    event.endDate = range.endAt
    event.isAllDay = isAllDay

    if let availability = input.availability {
      guard let destination = event.calendar else {
        throw CalendarEventRuntimeError.defaultCalendarUnavailable
      }
      try validateAvailability(availability, for: destination)
      event.availability = EKEventAvailability(availability)
    }
    if let alarms = input.alarms {
      event.alarms = try alarms.map(makeEventAlarm(from:))
    }
    if let recurrenceRules = input.recurrenceRules {
      try validateRecurrenceEndDates(recurrenceRules, eventStart: range.startAt)
      event.recurrenceRules = try recurrenceRules.map(makeRecurrenceRule(from:))
    }

    try eventStore.save(event, span: span.eventKitSpan)
    return Self.makeEventRecord(from: event)
  }

  func deleteEvent(
    _ reference: CalendarEventReference,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord {
    let event = try resolveEvent(reference)
    try requireWritable(event, reference: reference)
    let deleted = Self.makeEventRecord(from: event)
    try eventStore.remove(event, span: span.eventKitSpan)
    return deleted
  }

  private func validatedTitle(_ rawValue: String) throws -> String {
    let title = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "title",
        reason: "title must not be empty"
      )
    }
    return title
  }

  private func normalizedRange(
    startAt: Date,
    endAt: Date,
    isAllDay: Bool
  ) throws -> (startAt: Date, endAt: Date) {
    if isAllDay {
      let start = calendar.startOfDay(for: startAt)
      let end = calendar.startOfDay(for: endAt)
      guard end > start else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "end_at",
          reason: "all-day end_at is exclusive and must be a calendar day after start_at"
        )
      }
      return (start, end)
    }

    guard endAt >= startAt else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "end_at",
        reason: "end_at must be later than or equal to start_at"
      )
    }
    return (startAt, endAt)
  }

  private func resolveTimeZone(_ identifier: String?, argument: String) throws -> TimeZone? {
    guard let identifier else {
      return nil
    }
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let timeZone = TimeZone(identifier: trimmed) else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: argument,
        reason: "unknown IANA time zone '\(identifier)'"
      )
    }
    return timeZone
  }

  private func applyTimeZone(
    _ update: CalendarFieldUpdate<String>,
    to event: EKEvent
  ) throws {
    switch update {
    case .unchanged:
      break
    case .set(let identifier):
      event.timeZone = try resolveTimeZone(identifier, argument: "time_zone")
    case .clear:
      event.timeZone = nil
    }
  }

  private func apply<Value>(
    _ update: CalendarFieldUpdate<Value>,
    to value: inout Value?
  ) throws where Value: Equatable & Sendable {
    switch update {
    case .unchanged:
      break
    case .set(let newValue):
      value = newValue
    case .clear:
      value = nil
    }
  }

  private func validateAvailability(
    _ availability: CalendarAvailabilityFilter,
    for calendar: EKCalendar
  ) throws {
    let supported = calendar.supportedEventAvailabilities
    let isSupported: Bool
    switch availability {
    case .busy:
      isSupported = supported.contains(.busy)
    case .free:
      isSupported = supported.contains(.free)
    case .tentative:
      isSupported = supported.contains(.tentative)
    case .unavailable:
      isSupported = supported.contains(.unavailable)
    }
    guard isSupported else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "availability",
        reason: "calendar '\(calendar.title)' does not support '\(availability.rawValue)'"
      )
    }
  }

  private func validateRecurrenceEndDates(
    _ rules: [CalendarRecurrenceRule],
    eventStart: Date
  ) throws {
    for rule in rules {
      if case .endDate(let endDate) = rule.end, endDate < eventStart {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "recurrence.end_date",
          reason: "end date must be later than or equal to the event start"
        )
      }
    }
  }
}
