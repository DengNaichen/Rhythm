import EventKit

extension EKEventAvailability {
  nonisolated init(_ value: CalendarAvailabilityFilter) {
    switch value {
    case .busy:
      self = .busy
    case .free:
      self = .free
    case .tentative:
      self = .tentative
    case .unavailable:
      self = .unavailable
    }
  }

  nonisolated var stringValue: String {
    switch self {
    case .busy:
      return CalendarAvailabilityFilter.busy.rawValue
    case .free:
      return CalendarAvailabilityFilter.free.rawValue
    case .tentative:
      return CalendarAvailabilityFilter.tentative.rawValue
    case .unavailable:
      return CalendarAvailabilityFilter.unavailable.rawValue
    default:
      return "unknown"
    }
  }
}

extension EKEventStatus {
  nonisolated var mcpStatusValue: String {
    switch self {
    case .none:
      return CalendarEventStatusFilter.none.rawValue
    case .tentative:
      return CalendarEventStatusFilter.tentative.rawValue
    case .confirmed:
      return CalendarEventStatusFilter.confirmed.rawValue
    case .canceled:
      return CalendarEventStatusFilter.canceled.rawValue
    @unknown default:
      return CalendarEventStatusFilter.none.rawValue
    }
  }
}

extension CalendarEventSpan {
  nonisolated var eventKitSpan: EKSpan {
    switch self {
    case .thisEvent:
      return .thisEvent
    case .futureEvents:
      return .futureEvents
    }
  }
}

extension CalendarRecurrenceFrequency {
  nonisolated var eventKitFrequency: EKRecurrenceFrequency {
    switch self {
    case .daily:
      return .daily
    case .weekly:
      return .weekly
    case .monthly:
      return .monthly
    case .yearly:
      return .yearly
    }
  }
}

extension EKRecurrenceFrequency {
  nonisolated var calendarFrequency: CalendarRecurrenceFrequency {
    switch self {
    case .daily:
      return .daily
    case .weekly:
      return .weekly
    case .monthly:
      return .monthly
    case .yearly:
      return .yearly
    @unknown default:
      return .daily
    }
  }
}

extension CalendarWeekday {
  nonisolated var eventKitWeekday: EKWeekday {
    switch self {
    case .sunday:
      return .sunday
    case .monday:
      return .monday
    case .tuesday:
      return .tuesday
    case .wednesday:
      return .wednesday
    case .thursday:
      return .thursday
    case .friday:
      return .friday
    case .saturday:
      return .saturday
    }
  }
}

extension EKWeekday {
  nonisolated var calendarWeekday: CalendarWeekday {
    switch self {
    case .sunday:
      return .sunday
    case .monday:
      return .monday
    case .tuesday:
      return .tuesday
    case .wednesday:
      return .wednesday
    case .thursday:
      return .thursday
    case .friday:
      return .friday
    case .saturday:
      return .saturday
    @unknown default:
      return .sunday
    }
  }
}

extension EKParticipantStatus {
  nonisolated var calendarStatus: CalendarParticipantStatus {
    switch self {
    case .unknown:
      return .unknown
    case .pending:
      return .pending
    case .accepted:
      return .accepted
    case .declined:
      return .declined
    case .tentative:
      return .tentative
    case .delegated:
      return .delegated
    case .completed:
      return .completed
    case .inProcess:
      return .inProcess
    @unknown default:
      return .unknown
    }
  }
}

extension EKParticipantRole {
  nonisolated var calendarRole: CalendarParticipantRole {
    switch self {
    case .unknown:
      return .unknown
    case .required:
      return .required
    case .optional:
      return .optional
    case .chair:
      return .chair
    case .nonParticipant:
      return .nonParticipant
    @unknown default:
      return .unknown
    }
  }
}

extension EKParticipantType {
  nonisolated var calendarType: CalendarParticipantType {
    switch self {
    case .unknown:
      return .unknown
    case .person:
      return .person
    case .room:
      return .room
    case .resource:
      return .resource
    case .group:
      return .group
    @unknown default:
      return .unknown
    }
  }
}

extension EKAlarmType {
  nonisolated var calendarAction: CalendarAlarmAction {
    switch self {
    case .display:
      return .display
    case .audio:
      return .audio
    case .procedure:
      return .procedure
    case .email:
      return .email
    @unknown default:
      return .unknown
    }
  }
}
