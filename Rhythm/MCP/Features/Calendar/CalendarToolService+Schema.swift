import Foundation
import JSONSchema
import OrderedCollections

extension CalendarToolService {
  var eventReferenceProperties: OrderedDictionary<String, JSONSchema> {
    [
      "id": .string(
        description:
          "Opaque EventKit event ID returned by Calendar tools. Refetch after moving or externally syncing an event.",
        minLength: 1
      ),
      "occurrence_start": dateTimeSchema(
        "Actual start date-time of a recurring occurrence. Required for recurring update and delete operations."
      ),
      "original_start_at": dateTimeSchema(
        "Original EventKit start date-time. Required with occurrence_start for recurring update and delete operations."
      ),
    ]
  }

  var calendarReferenceProperties: OrderedDictionary<String, JSONSchema> {
    [
      "calendar_id": .string(
        description: "Exact calendar ID from calendar_calendars_list.",
        minLength: 1
      ),
      "list_name": .string(
        description:
          "Deprecated calendar title reference. It must resolve to exactly one calendar.",
        minLength: 1
      ),
    ]
  }

  var eventCreateProperties: OrderedDictionary<String, JSONSchema> {
    var properties: OrderedDictionary<String, JSONSchema> = [
      "title": .string(),
      "start_at": dateTimeSchema("Event start date/time."),
      "end_at": dateTimeSchema(
        "Event end date/time. For all-day events this is exclusive; use the next date for a one-day event."
      ),
      "location": .string(),
      "notes": .string(),
      "url": .string(format: .uri),
      "time_zone": .string(description: "IANA time zone identifier, such as Asia/Shanghai."),
      "is_all_day": .boolean(default: false),
      "availability": availabilitySchema(),
      "alarms": alarmsSchema(nullable: false),
      "recurrence": recurrenceSchema(nullable: false),
    ]
    properties.merge(calendarReferenceProperties) { _, reference in reference }
    return properties
  }

  var eventUpdateProperties: OrderedDictionary<String, JSONSchema> {
    var properties: OrderedDictionary<String, JSONSchema> = [
      "title": .string(),
      "start_at": dateTimeSchema("Replacement event start date/time."),
      "end_at": dateTimeSchema(
        "Replacement event end date/time. For all-day events this is exclusive."
      ),
      "location": nullableStringSchema("Replacement location. Null clears it."),
      "notes": nullableStringSchema("Replacement notes. Null clears them."),
      "url": nullableURIStringSchema("Replacement URL. Null clears it."),
      "time_zone": nullableStringSchema(
        "Replacement IANA time zone identifier. Null clears it."
      ),
      "is_all_day": .boolean(),
      "availability": availabilitySchema(),
      "alarms": alarmsSchema(nullable: true),
      "recurrence": recurrenceSchema(nullable: true),
    ]
    properties.merge(calendarReferenceProperties) { _, reference in reference }
    return properties
  }

  func eventRangeSchema(
    additionalProperties: OrderedDictionary<String, JSONSchema> = [:],
    required: [String] = []
  ) -> JSONSchema {
    var properties: OrderedDictionary<String, JSONSchema> = [
      "from": dateTimeSchema(
        "Start date/time. Date-only uses local midnight; omitted timezone uses local time."
      ),
      "to": dateTimeSchema(
        "End date/time. A date-only value includes the full local day."
      ),
      "calendar_ids": .array(
        description: "Exact calendar IDs from calendar_calendars_list.",
        items: .string(minLength: 1),
        minItems: 1,
        uniqueItems: true
      ),
      "list_names": .array(
        description:
          "Deprecated calendar titles. Every title must resolve to exactly one calendar.",
        items: .string(minLength: 1),
        minItems: 1,
        uniqueItems: true
      ),
    ]
    properties.merge(additionalProperties) { _, additional in additional }
    return .object(
      properties: properties,
      required: required,
      additionalProperties: false
    )
  }

  func statusSchema() -> JSONSchema {
    .string(
      description: "Filter by event status.",
      enum: CalendarEventStatusFilter.allCases.map { .string($0.rawValue) }
    )
  }

  func availabilitySchema() -> JSONSchema {
    .string(
      description: "Event availability.",
      enum: CalendarAvailabilityFilter.allCases.map { .string($0.rawValue) }
    )
  }

  func eventSpanSchema() -> JSONSchema {
    .string(
      description:
        "Recurring edit span: only this occurrence, or this and all future occurrences.",
      default: .string("this_event"),
      enum: [.string("this_event"), .string("future_events")]
    )
  }

  func alarmsSchema(nullable: Bool) -> JSONSchema {
    let emailAddress = JSONSchema.string(
      description: "Optional email address associated with the alarm.",
      format: .email
    )
    let relative = JSONSchema.object(
      properties: [
        "type": .string(const: .string(CalendarAlarmKind.relative.rawValue)),
        "minutes": .integer(
          description: "Non-negative minutes before the event for a relative alarm.",
          minimum: 0,
          maximum: CalendarAlarmInput.maximumRelativeMinutes
        ),
        "email_address": emailAddress,
      ],
      required: ["type", "minutes"],
      additionalProperties: false
    )
    let absolute = JSONSchema.object(
      properties: [
        "type": .string(const: .string(CalendarAlarmKind.absolute.rawValue)),
        "at": dateTimeSchema("Absolute alarm date/time."),
        "email_address": emailAddress,
      ],
      required: ["type", "at"],
      additionalProperties: false
    )
    let proximity = JSONSchema.object(
      properties: [
        "type": .string(const: .string(CalendarAlarmKind.proximity.rawValue)),
        "proximity": .string(
          default: .string(AlarmProximityKind.enter.rawValue),
          enum: AlarmProximityKind.allCases.map { .string($0.rawValue) }
        ),
        "location_title": .string(),
        "latitude": .number(minimum: -90, maximum: 90),
        "longitude": .number(minimum: -180, maximum: 180),
        "radius": .number(default: .int(200), exclusiveMinimum: 0),
        "email_address": emailAddress,
      ],
      required: ["type", "location_title", "latitude", "longitude"],
      additionalProperties: false
    )
    let alarm = JSONSchema.oneOf([relative, absolute, proximity])
    let array = JSONSchema.array(items: alarm, maxItems: 20)
    return nullable ? .anyOf([array, .null]) : array
  }

  func recurrenceSchema(nullable: Bool) -> JSONSchema {
    let recurrence = JSONSchema.object(
      properties: [
        "frequency": .string(
          enum: ["daily", "weekly", "monthly", "yearly"].map(JSONValue.string)
        ),
        "interval": .integer(
          default: .int(1),
          minimum: 1,
          maximum: CalendarRecurrenceRule.maximumInterval
        ),
        "by_day": .array(
          description: "RFC 5545 BYDAY values such as MO, FR, 1MO, or -1SU.",
          items: .string(minLength: 1),
          maxItems: 366,
          uniqueItems: true
        ),
        "by_month_day": integerArraySchema(minimum: -31, maximum: 31, excludesZero: true),
        "by_month": integerArraySchema(minimum: 1, maximum: 12),
        "by_week_no": integerArraySchema(minimum: -53, maximum: 53, excludesZero: true),
        "by_year_day": integerArraySchema(minimum: -366, maximum: 366, excludesZero: true),
        "by_set_pos": integerArraySchema(minimum: -366, maximum: 366, excludesZero: true),
        "end_at": dateTimeSchema("Recurrence end date/time (inclusive)."),
        "occurrence_count": .integer(minimum: 1),
      ],
      required: ["frequency"],
      additionalProperties: false
    )
    return nullable ? .anyOf([recurrence, .null]) : recurrence
  }

  private func dateTimeSchema(_ description: String) -> JSONSchema {
    .anyOf([
      .string(description: description, format: .date),
      .string(description: description, format: .dateTime),
      .string(
        description: description,
        pattern: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?$"#
      ),
    ])
  }

  private func nullableStringSchema(_ description: String) -> JSONSchema {
    .anyOf([.string(description: description), .null])
  }

  private func nullableURIStringSchema(_ description: String) -> JSONSchema {
    .anyOf([.string(description: description, format: .uri), .null])
  }

  private func integerArraySchema(
    minimum: Int,
    maximum: Int,
    excludesZero: Bool = false
  ) -> JSONSchema {
    let item: JSONSchema =
      excludesZero
      ? .anyOf([
        .integer(minimum: minimum, maximum: -1),
        .integer(minimum: 1, maximum: maximum),
      ])
      : .integer(minimum: minimum, maximum: maximum)
    return .array(
      items: item,
      maxItems: 366,
      uniqueItems: true
    )
  }
}
