import Foundation
import JSONSchema
import OrderedCollections

extension CalendarToolService {
  func listCalendarsTool() -> Tool {
    Tool(
      name: "calendar_calendars_list",
      title: "List Calendars",
      description: "List calendars with opaque IDs and editability metadata.",
      systemImage: "list.bullet.rectangle",
      inputSchema: .object(additionalProperties: false),
      readOnlyHint: true,
      openWorldHint: false
    ) { _ in
      try CalendarListUseCase(runtime: self.runtime).execute()
    }
  }

  func fetchEventsTool() -> Tool {
    Tool(
      name: "calendar_events_fetch",
      title: "Fetch Events",
      description: "Fetch calendar events with date range, calendar, and event filters.",
      systemImage: "magnifyingglass",
      inputSchema: eventRangeSchema(
        additionalProperties: [
          "query": .string(
            description: "Case-insensitive search against title, location, and notes."
          ),
          "include_all_day": .boolean(default: true),
          "status": statusSchema(),
          "availability": availabilitySchema(),
          "has_alarms": .boolean(),
          "is_recurring": .boolean(),
        ]
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try CalendarEventsFetchUseCase(
        runtime: self.runtime,
        now: self.now,
        calendar: self.calendar
      )
      .execute(arguments: arguments)
    }
  }

  func getEventTool() -> Tool {
    Tool(
      name: "calendar_events_get",
      title: "Get Event",
      description: "Get one event by its opaque event ID and optional recurring occurrence.",
      systemImage: "calendar",
      inputSchema: .object(
        properties: eventReferenceProperties,
        required: ["id"],
        additionalProperties: false
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try CalendarEventGetUseCase(runtime: self.runtime, calendar: self.calendar)
        .execute(arguments: arguments)
    }
  }

  func freeBusyTool() -> Tool {
    Tool(
      name: "calendar_free_busy",
      title: "Calendar Free/Busy",
      description:
        "Return merged busy windows and explicit overlap conflicts for a date range.",
      systemImage: "calendar.badge.clock",
      inputSchema: eventRangeSchema(
        additionalProperties: [
          "include_all_day": .boolean(default: true),
          "include_tentative": .boolean(default: true),
        ],
        required: ["from", "to"]
      ),
      readOnlyHint: true,
      openWorldHint: false
    ) { arguments in
      try CalendarFreeBusyUseCase(
        runtime: self.runtime,
        now: self.now,
        calendar: self.calendar
      )
      .execute(arguments: arguments)
    }
  }
}
