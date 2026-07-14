import Foundation

struct CalendarEventsFetchUseCase {
  let runtime: EventKitRuntime
  let now: () -> Date
  let calendar: Calendar

  init(
    runtime: EventKitRuntime,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = .eventKitGregorian
  ) {
    self.runtime = runtime
    self.now = now
    self.calendar = calendar
  }

  func execute(arguments: [String: Value]) throws -> [CalendarEventDTO] {
    try requireCalendarAuthorization(runtime)
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let range = try DateRangeNormalizer.normalizeCalendarRange(
      from: try decoder.optionalString("from"),
      to: try decoder.optionalString("to"),
      now: now,
      calendar: calendar
    )

    let input = CalendarEventsFetchInput(
      range: range,
      calendars: try decoder.calendarReferences(),
      query: try decoder.optionalString("query"),
      includeAllDay: try decoder.optionalBool("include_all_day") ?? true,
      status: try decoder.optionalEnumValue(for: "status", as: CalendarEventStatusFilter.self),
      availability: try decoder.optionalEnumValue(
        for: "availability",
        as: CalendarAvailabilityFilter.self
      ),
      hasAlarms: try decoder.optionalBool("has_alarms"),
      isRecurring: try decoder.optionalBool("is_recurring")
    )

    return try runtime.fetchEvents(input)
      .sorted {
        if $0.startAt == $1.startAt { return $0.id < $1.id }
        return $0.startAt < $1.startAt
      }
      .map(CalendarEventDTO.init)
  }
}

struct CalendarEventGetUseCase {
  let runtime: EventKitRuntime
  let calendar: Calendar

  func execute(arguments: [String: Value]) throws -> CalendarEventDTO {
    try requireCalendarAuthorization(runtime)
    let reference = try ToolArgumentsDecoder(arguments: arguments)
      .eventReference(calendar: calendar)
    return CalendarEventDTO(try runtime.event(reference))
  }
}
