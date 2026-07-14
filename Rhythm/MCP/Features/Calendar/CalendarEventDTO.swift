import Foundation

nonisolated struct EventKitListDTO: Encodable, Equatable {
  let id: String
  let title: String
  let source: String
  let color: String
  let isEditable: Bool
  let isSubscribed: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case source
    case color
    case isEditable = "is_editable"
    case isSubscribed = "is_subscribed"
  }

  init(_ record: EventKitListRecord) {
    id = record.id
    title = record.title
    source = record.source
    color = record.color
    isEditable = record.isEditable
    isSubscribed = record.isSubscribed
  }
}

nonisolated struct CalendarEventDTO: Encodable, Equatable {
  let id: String
  let externalID: String?
  let title: String
  let startAt: String
  let endAt: String
  let startDate: String?
  let endDate: String?
  let isAllDay: Bool
  let location: String?
  let structuredLocation: CalendarStructuredLocationDTO?
  let notes: String?
  let url: String?
  let status: String
  let availability: String
  let timeZone: String?
  let createdAt: String?
  let modifiedAt: String?
  let calendarID: String
  let calendarTitle: String
  let alarms: [CalendarAlarmDTO]
  let recurrenceRules: [CalendarRecurrenceDTO]
  let organizer: CalendarParticipantDTO?
  let attendees: [CalendarParticipantDTO]
  let occurrenceStart: String?
  let originalStartAt: String?
  let isDetached: Bool
  let hasAlarms: Bool
  let isRecurring: Bool
  let listTitle: String

  enum CodingKeys: String, CodingKey {
    case id
    case externalID = "external_id"
    case title
    case startAt = "start_at"
    case endAt = "end_at"
    case startDate = "start_date"
    case endDate = "end_date"
    case isAllDay = "is_all_day"
    case location
    case structuredLocation = "structured_location"
    case notes
    case url
    case status
    case availability
    case timeZone = "time_zone"
    case createdAt = "created_at"
    case modifiedAt = "modified_at"
    case calendarID = "calendar_id"
    case calendarTitle = "calendar_title"
    case alarms
    case recurrenceRules = "recurrence_rules"
    case organizer
    case attendees
    case occurrenceStart = "occurrence_start"
    case originalStartAt = "original_start_at"
    case isDetached = "is_detached"
    case hasAlarms = "has_alarms"
    case isRecurring = "is_recurring"
    case listTitle = "list_title"
  }

  init(_ record: CalendarEventRecord) {
    id = record.id
    externalID = record.externalID
    title = record.title
    startAt = EventKitDateFormatting.iso8601String(from: record.startAt)
    endAt = EventKitDateFormatting.iso8601String(from: record.endAt)
    startDate =
      record.isAllDay
      ? EventKitDateFormatting.localDateString(from: record.startAt) : nil
    endDate =
      record.isAllDay
      ? EventKitDateFormatting.localDateString(from: record.endAt) : nil
    isAllDay = record.isAllDay
    location = record.location
    structuredLocation = record.structuredLocation.map(CalendarStructuredLocationDTO.init)
    notes = record.notes
    url = record.url
    status = record.status
    availability = record.availability
    timeZone = record.timeZoneIdentifier
    createdAt = record.createdAt.map(EventKitDateFormatting.iso8601String(from:))
    modifiedAt = record.modifiedAt.map(EventKitDateFormatting.iso8601String(from:))
    calendarID = record.calendarID
    calendarTitle = record.calendarTitle
    alarms = record.alarms.map(CalendarAlarmDTO.init)
    recurrenceRules = record.recurrenceRules.map(CalendarRecurrenceDTO.init)
    organizer = record.organizer.map(CalendarParticipantDTO.init)
    attendees = record.attendees.map(CalendarParticipantDTO.init)
    occurrenceStart = record.occurrenceStart.map(EventKitDateFormatting.iso8601String(from:))
    originalStartAt = record.originalStartAt.map(EventKitDateFormatting.iso8601String(from:))
    isDetached = record.isDetached
    hasAlarms = record.hasAlarms
    isRecurring = record.isRecurring
    listTitle = record.calendarTitle
  }
}

nonisolated struct CalendarStructuredLocationDTO: Encodable, Equatable {
  let title: String
  let latitude: Double?
  let longitude: Double?
  let radius: Double?

  init(_ record: CalendarStructuredLocationRecord) {
    title = record.title
    latitude = record.latitude
    longitude = record.longitude
    radius = record.radius
  }
}

nonisolated struct CalendarAlarmDTO: Encodable, Equatable {
  let type: String
  let minutes: Int?
  let at: String?
  let proximity: String?
  let locationTitle: String?
  let latitude: Double?
  let longitude: Double?
  let radius: Double?
  let action: String
  let emailAddress: String?
  let soundName: String?

  enum CodingKeys: String, CodingKey {
    case type
    case minutes
    case at
    case proximity
    case locationTitle = "location_title"
    case latitude
    case longitude
    case radius
    case action
    case emailAddress = "email_address"
    case soundName = "sound_name"
  }

  init(_ record: CalendarAlarmRecord) {
    type = record.kind.rawValue
    if let offset = record.relativeOffsetMinutes {
      let minutesBefore = (-offset).rounded()
      if minutesBefore.isFinite,
        (0...Double(CalendarAlarmInput.maximumRelativeMinutes)).contains(minutesBefore)
      {
        minutes = Int(minutesBefore)
      } else {
        minutes = nil
      }
    } else {
      minutes = nil
    }
    at = record.absoluteAt.map(EventKitDateFormatting.iso8601String(from:))
    proximity = record.proximity?.rawValue
    locationTitle = record.locationTitle
    latitude = record.latitude
    longitude = record.longitude
    radius = record.radius
    action = record.action.rawValue
    emailAddress = record.emailAddress
    soundName = record.soundName
  }
}

nonisolated struct CalendarRecurrenceDTO: Encodable, Equatable {
  let frequency: String
  let interval: Int
  let byDay: [String]
  let byMonthDay: [Int]
  let byMonth: [Int]
  let byWeekNumber: [Int]
  let byYearDay: [Int]
  let bySetPosition: [Int]
  let firstDayOfWeek: String?
  let endAt: String?
  let occurrenceCount: Int?

  enum CodingKeys: String, CodingKey {
    case frequency
    case interval
    case byDay = "by_day"
    case byMonthDay = "by_month_day"
    case byMonth = "by_month"
    case byWeekNumber = "by_week_no"
    case byYearDay = "by_year_day"
    case bySetPosition = "by_set_pos"
    case firstDayOfWeek = "first_day_of_week"
    case endAt = "end_at"
    case occurrenceCount = "occurrence_count"
  }

  init(_ rule: CalendarRecurrenceRule) {
    frequency = rule.frequency.rawValue
    interval = rule.interval
    byDay = rule.daysOfTheWeek.map(Self.weekdayString)
    byMonthDay = rule.daysOfTheMonth
    byMonth = rule.monthsOfTheYear
    byWeekNumber = rule.weeksOfTheYear
    byYearDay = rule.daysOfTheYear
    bySetPosition = rule.setPositions
    firstDayOfWeek = rule.firstDayOfTheWeek?.rawValue
    switch rule.end {
    case .endDate(let date):
      endAt = EventKitDateFormatting.iso8601String(from: date)
      occurrenceCount = nil
    case .occurrenceCount(let count):
      endAt = nil
      occurrenceCount = count
    case nil:
      endAt = nil
      occurrenceCount = nil
    }
  }

  private static func weekdayString(_ weekday: CalendarRecurrenceWeekday) -> String {
    let code: String
    switch weekday.day {
    case .sunday: code = "SU"
    case .monday: code = "MO"
    case .tuesday: code = "TU"
    case .wednesday: code = "WE"
    case .thursday: code = "TH"
    case .friday: code = "FR"
    case .saturday: code = "SA"
    }
    return weekday.weekNumber == 0 ? code : "\(weekday.weekNumber)\(code)"
  }
}

nonisolated struct CalendarParticipantDTO: Encodable, Equatable {
  let name: String?
  let url: String
  let status: String
  let role: String
  let type: String
  let isCurrentUser: Bool

  enum CodingKeys: String, CodingKey {
    case name
    case url
    case status
    case role
    case type
    case isCurrentUser = "is_current_user"
  }

  init(_ record: CalendarParticipantRecord) {
    name = record.name
    url = record.url
    status = record.status.rawValue
    role = record.role.rawValue
    type = record.type.rawValue
    isCurrentUser = record.isCurrentUser
  }
}
