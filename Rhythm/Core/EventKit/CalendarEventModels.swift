import Foundation

nonisolated struct CalendarStructuredLocationRecord: Equatable, Sendable {
  let title: String
  let latitude: Double?
  let longitude: Double?
  let radius: Double?
}

nonisolated enum CalendarParticipantStatus: String, Sendable {
  case unknown
  case pending
  case accepted
  case declined
  case tentative
  case delegated
  case completed
  case inProcess = "in_process"
}

nonisolated enum CalendarParticipantRole: String, Sendable {
  case unknown
  case required
  case optional
  case chair
  case nonParticipant = "non_participant"
}

nonisolated enum CalendarParticipantType: String, Sendable {
  case unknown
  case person
  case room
  case resource
  case group
}

nonisolated struct CalendarParticipantRecord: Equatable, Sendable {
  let name: String?
  let url: String
  let status: CalendarParticipantStatus
  let role: CalendarParticipantRole
  let type: CalendarParticipantType
  let isCurrentUser: Bool
}

nonisolated struct CalendarOccurrenceRecord: Equatable, Sendable {
  let originalStartAt: Date
  let isDetached: Bool
}

nonisolated struct CalendarEventRecord: Equatable, Sendable, Identifiable {
  let id: String
  let externalID: String?
  let title: String
  let startAt: Date
  let endAt: Date
  let isAllDay: Bool
  let location: String?
  let structuredLocation: CalendarStructuredLocationRecord?
  let notes: String?
  let url: String?
  let status: String
  let availability: String
  let timeZoneIdentifier: String?
  let createdAt: Date?
  let modifiedAt: Date?
  let calendarID: String
  let calendarTitle: String
  let alarms: [CalendarAlarmRecord]
  let recurrenceRules: [CalendarRecurrenceRule]
  let organizer: CalendarParticipantRecord?
  let attendees: [CalendarParticipantRecord]
  let occurrence: CalendarOccurrenceRecord?

  var hasAlarms: Bool { !alarms.isEmpty }
  var isRecurring: Bool { !recurrenceRules.isEmpty || occurrence != nil }
  var listTitle: String { calendarTitle }
  var occurrenceStart: Date? { occurrence == nil ? nil : startAt }
  var originalStartAt: Date? { occurrence?.originalStartAt }
  var isDetached: Bool { occurrence?.isDetached ?? false }
  var reference: CalendarEventReference {
    CalendarEventReference(
      id: id,
      occurrenceStart: occurrenceStart,
      originalStartAt: originalStartAt
    )
  }

  init(
    id: String,
    externalID: String? = nil,
    title: String,
    startAt: Date,
    endAt: Date,
    isAllDay: Bool,
    location: String? = nil,
    structuredLocation: CalendarStructuredLocationRecord? = nil,
    notes: String? = nil,
    url: String? = nil,
    status: String,
    availability: String,
    timeZoneIdentifier: String? = nil,
    createdAt: Date? = nil,
    modifiedAt: Date? = nil,
    calendarID: String,
    calendarTitle: String,
    alarms: [CalendarAlarmRecord] = [],
    recurrenceRules: [CalendarRecurrenceRule] = [],
    organizer: CalendarParticipantRecord? = nil,
    attendees: [CalendarParticipantRecord] = [],
    occurrence: CalendarOccurrenceRecord? = nil
  ) {
    self.id = id
    self.externalID = externalID
    self.title = title
    self.startAt = startAt
    self.endAt = endAt
    self.isAllDay = isAllDay
    self.location = location
    self.structuredLocation = structuredLocation
    self.notes = notes
    self.url = url
    self.status = status
    self.availability = availability
    self.timeZoneIdentifier = timeZoneIdentifier
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.calendarID = calendarID
    self.calendarTitle = calendarTitle
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
    self.organizer = organizer
    self.attendees = attendees
    self.occurrence = occurrence
  }
}

nonisolated struct CalendarEventsFetchInput: Equatable, Sendable {
  let range: DateRange
  let calendars: [EventKitCalendarReference]?
  let query: String?
  let includeAllDay: Bool
  let status: CalendarEventStatusFilter?
  let availability: CalendarAvailabilityFilter?
  let hasAlarms: Bool?
  let isRecurring: Bool?

  init(
    range: DateRange,
    calendars: [EventKitCalendarReference]? = nil,
    query: String? = nil,
    includeAllDay: Bool = true,
    status: CalendarEventStatusFilter? = nil,
    availability: CalendarAvailabilityFilter? = nil,
    hasAlarms: Bool? = nil,
    isRecurring: Bool? = nil
  ) {
    self.range = range
    self.calendars = calendars
    self.query = query
    self.includeAllDay = includeAllDay
    self.status = status
    self.availability = availability
    self.hasAlarms = hasAlarms
    self.isRecurring = isRecurring
  }
}

nonisolated struct CalendarEventCreateInput: Equatable, Sendable {
  let title: String
  let startAt: Date
  let endAt: Date
  let calendar: EventKitCalendarReference?
  let location: String?
  let notes: String?
  let url: URL?
  let timeZoneIdentifier: String?
  let isAllDay: Bool
  let availability: CalendarAvailabilityFilter?
  let alarms: [CalendarAlarmInput]
  let recurrenceRules: [CalendarRecurrenceRule]

  init(
    title: String,
    startAt: Date,
    endAt: Date,
    calendar: EventKitCalendarReference? = nil,
    location: String? = nil,
    notes: String? = nil,
    url: URL? = nil,
    timeZoneIdentifier: String? = nil,
    isAllDay: Bool = false,
    availability: CalendarAvailabilityFilter? = nil,
    alarms: [CalendarAlarmInput] = [],
    recurrenceRules: [CalendarRecurrenceRule] = []
  ) {
    self.title = title
    self.startAt = startAt
    self.endAt = endAt
    self.calendar = calendar
    self.location = location
    self.notes = notes
    self.url = url
    self.timeZoneIdentifier = timeZoneIdentifier
    self.isAllDay = isAllDay
    self.availability = availability
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}

nonisolated struct CalendarEventUpdateInput: Equatable, Sendable {
  let title: String?
  let startAt: Date?
  let endAt: Date?
  let calendar: EventKitCalendarReference?
  let location: CalendarFieldUpdate<String>
  let notes: CalendarFieldUpdate<String>
  let url: CalendarFieldUpdate<URL>
  let timeZoneIdentifier: CalendarFieldUpdate<String>
  let isAllDay: Bool?
  let availability: CalendarAvailabilityFilter?
  let alarms: [CalendarAlarmInput]?
  let recurrenceRules: [CalendarRecurrenceRule]?

  init(
    title: String? = nil,
    startAt: Date? = nil,
    endAt: Date? = nil,
    calendar: EventKitCalendarReference? = nil,
    location: CalendarFieldUpdate<String> = .unchanged,
    notes: CalendarFieldUpdate<String> = .unchanged,
    url: CalendarFieldUpdate<URL> = .unchanged,
    timeZoneIdentifier: CalendarFieldUpdate<String> = .unchanged,
    isAllDay: Bool? = nil,
    availability: CalendarAvailabilityFilter? = nil,
    alarms: [CalendarAlarmInput]? = nil,
    recurrenceRules: [CalendarRecurrenceRule]? = nil
  ) {
    self.title = title
    self.startAt = startAt
    self.endAt = endAt
    self.calendar = calendar
    self.location = location
    self.notes = notes
    self.url = url
    self.timeZoneIdentifier = timeZoneIdentifier
    self.isAllDay = isAllDay
    self.availability = availability
    self.alarms = alarms
    self.recurrenceRules = recurrenceRules
  }
}
