import Foundation
import JSONSchema
import OrderedCollections

extension CalendarToolService {
  func createEventTool() -> Tool {
    Tool(
      name: "calendar_events_create",
      title: "Create Event",
      description: "Create a calendar event, including alarms and recurrence.",
      systemImage: "calendar.badge.plus",
      inputSchema: .object(
        properties: eventCreateProperties,
        required: ["title", "start_at", "end_at"],
        additionalProperties: false
      ),
      openWorldHint: true
    ) { arguments in
      try await CalendarEventCreateUseCase(runtime: self.runtime, calendar: self.calendar)
        .execute(arguments: arguments)
    }
  }

  func updateEventTool() -> Tool {
    var properties = eventReferenceProperties
    properties.merge(eventUpdateProperties) { _, update in update }
    properties["span"] = eventSpanSchema()

    return Tool(
      name: "calendar_events_update",
      title: "Update Event",
      description:
        "Update one event or this and future occurrences. Null clears nullable fields.",
      systemImage: "calendar.badge.exclamationmark",
      inputSchema: .object(
        properties: properties,
        required: ["id"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    ) { arguments in
      try await CalendarEventUpdateUseCase(runtime: self.runtime, calendar: self.calendar)
        .execute(arguments: arguments)
    }
  }

  func deleteEventTool() -> Tool {
    var properties = eventReferenceProperties
    properties["span"] = eventSpanSchema()
    properties["confirm"] = .boolean(
      description: "Must be true because the event will be deleted."
    )

    return Tool(
      name: "calendar_events_delete",
      title: "Delete Event",
      description: "Delete one event or this and all future occurrences.",
      systemImage: "calendar.badge.minus",
      inputSchema: .object(
        properties: properties,
        required: ["id", "confirm"],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true
    ) { arguments in
      try await CalendarEventDeleteUseCase(runtime: self.runtime, calendar: self.calendar)
        .execute(arguments: arguments)
    }
  }
}
