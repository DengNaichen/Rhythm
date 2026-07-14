import Foundation

struct CalendarEventCreateUseCase {
  let runtime: EventKitRuntime
  let calendar: Calendar

  init(runtime: EventKitRuntime, calendar: Calendar = .eventKitGregorian) {
    self.runtime = runtime
    self.calendar = calendar
  }

  func execute(arguments: [String: Value]) async throws -> CalendarEventDTO {
    try await runtime.requestEventAccess()
    try requireCalendarAuthorization(runtime)

    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let startAt = try decoder.date("start_at", calendar: calendar)
    let endAt = try decoder.date("end_at", calendar: calendar)
    let isAllDay = try decoder.optionalBool("is_all_day") ?? false
    try validateEventRange(
      startAt: startAt,
      endAt: endAt,
      isAllDay: isAllDay,
      calendar: calendar
    )

    let recurrence = try decoder.recurrence("recurrence", calendar: calendar)
    try validateRecurrence(
      recurrence,
      eventStart: isAllDay ? calendar.startOfDay(for: startAt) : startAt
    )

    let input = CalendarEventCreateInput(
      title: try decoder.requiredString("title"),
      startAt: startAt,
      endAt: endAt,
      calendar: try decoder.calendarReference(),
      location: try decoder.optionalString("location"),
      notes: try decoder.notes("notes"),
      url: try decoder.url("url"),
      timeZoneIdentifier: try decoder.timeZoneIdentifier("time_zone"),
      isAllDay: isAllDay,
      availability: try decoder.optionalEnumValue(
        for: "availability",
        as: CalendarAvailabilityFilter.self
      ),
      alarms: try decoder.alarms("alarms", calendar: calendar) ?? [],
      recurrenceRules: recurrence.map { [$0] } ?? []
    )

    return CalendarEventDTO(try runtime.createEvent(input))
  }
}

struct CalendarEventUpdateUseCase {
  let runtime: EventKitRuntime
  let calendar: Calendar

  init(runtime: EventKitRuntime, calendar: Calendar = .eventKitGregorian) {
    self.runtime = runtime
    self.calendar = calendar
  }

  func execute(arguments: [String: Value]) async throws -> CalendarEventDTO {
    try await runtime.requestEventAccess()
    try requireCalendarAuthorization(runtime)

    let decoder = ToolArgumentsDecoder(arguments: arguments)
    try requireMutation(arguments)
    let reference = try decoder.eventReference(calendar: calendar)
    let existing = try runtime.event(reference)
    try requireRecurringOccurrence(existing, reference: reference)
    let span = try decoder.eventSpan()
    if span == .futureEvents, !existing.isRecurring {
      throw ServiceToolError.invalidValue(
        argument: "span",
        reason: "future_events requires a recurring event"
      )
    }

    let startAt = try decoder.optionalDate("start_at", calendar: calendar)
    let endAt = try decoder.optionalDate("end_at", calendar: calendar)
    let isAllDay = try decoder.optionalBool("is_all_day")
    try validateEventRange(
      startAt: startAt ?? existing.startAt,
      endAt: endAt ?? existing.endAt,
      isAllDay: isAllDay ?? existing.isAllDay,
      calendar: calendar
    )

    let recurrenceUpdate = try decoder.recurrenceValuesUpdate(
      "recurrence",
      calendar: calendar
    )
    if let recurrence = recurrenceUpdate?.first {
      let effectiveStart = startAt ?? existing.startAt
      try validateRecurrence(
        recurrence,
        eventStart: (isAllDay ?? existing.isAllDay)
          ? calendar.startOfDay(for: effectiveStart) : effectiveStart
      )
    }

    let input = CalendarEventUpdateInput(
      title: arguments["title"] == nil ? nil : try decoder.requiredString("title"),
      startAt: startAt,
      endAt: endAt,
      calendar: try decoder.calendarReference(),
      location: try decoder.stringUpdate("location"),
      notes: try decoder.stringUpdate("notes", preserveWhitespace: true),
      url: try decoder.urlUpdate("url"),
      timeZoneIdentifier: try decoder.timeZoneUpdate("time_zone"),
      isAllDay: isAllDay,
      availability: try decoder.optionalEnumValue(
        for: "availability",
        as: CalendarAvailabilityFilter.self
      ),
      alarms: try decoder.alarmValuesUpdate("alarms", calendar: calendar),
      recurrenceRules: recurrenceUpdate
    )

    return CalendarEventDTO(
      try runtime.updateEvent(reference, input: input, span: span)
    )
  }

  private func requireMutation(_ arguments: [String: Value]) throws {
    let metadata = Set(["id", "occurrence_start", "original_start_at", "span"])
    guard arguments.keys.contains(where: { !metadata.contains($0) }) else {
      throw ServiceToolError.invalidValue(
        argument: "arguments",
        reason: "at least one event field must be updated"
      )
    }
  }
}

struct CalendarEventDeleteUseCase {
  let runtime: EventKitRuntime
  let calendar: Calendar

  init(runtime: EventKitRuntime, calendar: Calendar = .eventKitGregorian) {
    self.runtime = runtime
    self.calendar = calendar
  }

  func execute(arguments: [String: Value]) async throws -> CalendarEventDeleteResult {
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    guard try decoder.optionalBool("confirm") == true else {
      throw ServiceToolError.invalidValue(argument: "confirm", reason: "must be true")
    }

    try await runtime.requestEventAccess()
    try requireCalendarAuthorization(runtime)
    let reference = try decoder.eventReference(calendar: calendar)
    let span = try decoder.eventSpan()
    let existing = try runtime.event(reference)
    try requireRecurringOccurrence(existing, reference: reference)
    if span == .futureEvents, !existing.isRecurring {
      throw ServiceToolError.invalidValue(
        argument: "span",
        reason: "future_events requires a recurring event"
      )
    }
    let deleted = try runtime.deleteEvent(reference, span: span)
    return CalendarEventDeleteResult(
      deleted: true,
      id: deleted.id,
      occurrenceStart: reference.occurrenceStart.map(EventKitDateFormatting.iso8601String(from:)),
      originalStartAt: reference.originalStartAt.map(
        EventKitDateFormatting.iso8601String(from:)
      ),
      span: span.rawValue,
      title: deleted.title,
      calendarID: deleted.calendarID,
      calendarTitle: deleted.calendarTitle
    )
  }
}

private func validateEventRange(
  startAt: Date,
  endAt: Date,
  isAllDay: Bool,
  calendar: Calendar
) throws {
  if isAllDay {
    guard calendar.startOfDay(for: endAt) > calendar.startOfDay(for: startAt) else {
      throw ServiceToolError.invalidValue(
        argument: "end_at",
        reason: "all-day end_at is exclusive and must be a calendar day after start_at"
      )
    }
    return
  }
  guard endAt >= startAt else {
    throw ServiceToolError.invalidValue(
      argument: "end_at",
      reason: "must be later than or equal to start_at"
    )
  }
}

private func validateRecurrence(
  _ recurrence: CalendarRecurrenceRule?,
  eventStart: Date
) throws {
  if let recurrence {
    try CalendarRecurrenceValidator.validate(recurrence)
  }
  guard case .endDate(let endAt) = recurrence?.end, endAt < eventStart else { return }
  throw ServiceToolError.invalidValue(
    argument: "recurrence.end_at",
    reason: "must not be earlier than the event start"
  )
}

private func requireRecurringOccurrence(
  _ event: CalendarEventRecord,
  reference: CalendarEventReference
) throws {
  guard event.isRecurring else { return }
  guard reference.occurrenceStart != nil else {
    throw ServiceToolError.invalidValue(
      argument: "occurrence_start",
      reason: "is required to target a recurring event occurrence safely"
    )
  }
  guard reference.originalStartAt != nil else {
    throw ServiceToolError.invalidValue(
      argument: "original_start_at",
      reason: "is required to disambiguate a recurring event occurrence safely"
    )
  }
}

nonisolated struct CalendarEventDeleteResult: Encodable, Equatable {
  let deleted: Bool
  let id: String
  let occurrenceStart: String?
  let originalStartAt: String?
  let span: String
  let title: String
  let calendarID: String
  let calendarTitle: String

  enum CodingKeys: String, CodingKey {
    case deleted
    case id
    case occurrenceStart = "occurrence_start"
    case originalStartAt = "original_start_at"
    case span
    case title
    case calendarID = "calendar_id"
    case calendarTitle = "calendar_title"
  }
}
