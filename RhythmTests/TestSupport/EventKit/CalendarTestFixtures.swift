import Foundation

@testable import Rhythm

nonisolated enum CalendarTestFixtures {
  static let start = date("2026-07-14T09:00:00Z")
  static let end = date("2026-07-14T10:00:00Z")
  static let occurrenceStart = date("2026-07-21T10:00:00Z")
  static let originalStartAt = date("2026-07-21T09:00:00Z")

  static let writableCalendar = EventKitListRecord(
    id: "calendar-work",
    title: "Work",
    source: "iCloud",
    color: "Blue",
    isEditable: true,
    isSubscribed: false
  )

  static let readOnlyCalendar = EventKitListRecord(
    id: "calendar-holidays",
    title: "Holidays",
    source: "Subscribed",
    color: "Red",
    isEditable: false,
    isSubscribed: true
  )

  static let duplicateTitleCalendars = [
    EventKitListRecord(
      id: "calendar-team-a",
      title: "Team",
      source: "iCloud",
      color: "Green",
      isEditable: true,
      isSubscribed: false
    ),
    EventKitListRecord(
      id: "calendar-team-b",
      title: "Team",
      source: "Exchange",
      color: "Purple",
      isEditable: true,
      isSubscribed: false
    ),
  ]

  static var event: CalendarEventRecord {
    makeEvent()
  }

  static func makeEvent(
    id: String = "event-1",
    title: String = "Planning",
    startAt: Date = start,
    endAt: Date = end,
    isAllDay: Bool = false,
    status: String = CalendarEventStatusFilter.confirmed.rawValue,
    availability: String = CalendarAvailabilityFilter.busy.rawValue,
    calendarID: String = writableCalendar.id,
    calendarTitle: String = writableCalendar.title,
    alarms: [CalendarAlarmRecord] = [],
    recurrenceRules: [CalendarRecurrenceRule] = [],
    occurrence: CalendarOccurrenceRecord? = nil
  ) -> CalendarEventRecord {
    CalendarEventRecord(
      id: id,
      externalID: "external-\(id)",
      title: title,
      startAt: startAt,
      endAt: endAt,
      isAllDay: isAllDay,
      location: "Room 1",
      notes: "Agenda",
      url: "https://example.com/events/\(id)",
      status: status,
      availability: availability,
      timeZoneIdentifier: "UTC",
      createdAt: startAt.addingTimeInterval(-3_600),
      modifiedAt: startAt.addingTimeInterval(-1_800),
      calendarID: calendarID,
      calendarTitle: calendarTitle,
      alarms: alarms,
      recurrenceRules: recurrenceRules,
      occurrence: occurrence
    )
  }

  static func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
  }
}
