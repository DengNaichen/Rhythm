import AppKit
import CoreLocation
import EventKit
import Foundation

extension LiveEventKitRuntime {
  static func makeListRecord(from calendar: EKCalendar) -> EventKitListRecord {
    EventKitListRecord(
      id: calendar.calendarIdentifier,
      title: calendar.title,
      source: calendar.source.title,
      color: calendar.color.accessibilityName,
      isEditable: calendar.allowsContentModifications,
      isSubscribed: calendar.isSubscribed
    )
  }

  static func makeEventRecord(from event: EKEvent) -> CalendarEventRecord {
    let eventCalendar = event.calendar
    let recurrenceRules = (event.recurrenceRules ?? []).map(makeRecurrenceRecord(from:))
    let occurrence: CalendarOccurrenceRecord?
    if event.hasRecurrenceRules || event.isDetached, let occurrenceDate = event.occurrenceDate {
      occurrence = CalendarOccurrenceRecord(
        originalStartAt: occurrenceDate,
        isDetached: event.isDetached
      )
    } else {
      occurrence = nil
    }

    return CalendarEventRecord(
      id: event.eventIdentifier ?? event.calendarItemIdentifier,
      externalID: event.calendarItemExternalIdentifier,
      title: event.title ?? "",
      startAt: event.startDate,
      endAt: event.endDate ?? event.startDate,
      isAllDay: event.isAllDay,
      location: event.location,
      structuredLocation: event.structuredLocation.map(makeLocationRecord(from:)),
      notes: event.notes,
      url: event.url?.absoluteString,
      status: event.status.mcpStatusValue,
      availability: event.availability.stringValue,
      timeZoneIdentifier: event.timeZone?.identifier,
      createdAt: event.creationDate,
      modifiedAt: event.lastModifiedDate,
      calendarID: eventCalendar?.calendarIdentifier ?? "",
      calendarTitle: eventCalendar?.title ?? "",
      alarms: (event.alarms ?? []).map(makeAlarmRecord(from:)),
      recurrenceRules: recurrenceRules,
      organizer: event.organizer.map(makeParticipantRecord(from:)),
      attendees: (event.attendees ?? []).map(makeParticipantRecord(from:)),
      occurrence: occurrence
    )
  }

  static func makeAlarmRecord(from alarm: EKAlarm) -> CalendarAlarmRecord {
    let structuredLocation = alarm.structuredLocation
    let kind: CalendarAlarmKind
    let proximity: AlarmProximityKind?

    switch alarm.proximity {
    case .enter:
      kind = .proximity
      proximity = .enter
    case .leave:
      kind = .proximity
      proximity = .leave
    default:
      kind = alarm.absoluteDate == nil ? .relative : .absolute
      proximity = nil
    }

    return CalendarAlarmRecord(
      kind: kind,
      relativeOffsetMinutes: kind == .relative ? alarm.relativeOffset / 60 : nil,
      absoluteAt: alarm.absoluteDate,
      proximity: proximity,
      locationTitle: structuredLocation?.title,
      latitude: structuredLocation?.geoLocation?.coordinate.latitude,
      longitude: structuredLocation?.geoLocation?.coordinate.longitude,
      radius: structuredLocation?.radius,
      action: alarm.type.calendarAction,
      emailAddress: alarm.emailAddress,
      soundName: alarm.soundName
    )
  }

  static func makeRecurrenceRecord(from rule: EKRecurrenceRule) -> CalendarRecurrenceRule {
    let recurrenceEnd: CalendarRecurrenceEnd?
    if let end = rule.recurrenceEnd {
      if let endDate = end.endDate {
        recurrenceEnd = .endDate(endDate)
      } else if end.occurrenceCount > 0 {
        recurrenceEnd = .occurrenceCount(Int(end.occurrenceCount))
      } else {
        recurrenceEnd = nil
      }
    } else {
      recurrenceEnd = nil
    }

    let firstDayOfTheWeek: CalendarWeekday?
    if rule.firstDayOfTheWeek == 0 {
      firstDayOfTheWeek = nil
    } else {
      firstDayOfTheWeek = EKWeekday(rawValue: rule.firstDayOfTheWeek)?.calendarWeekday
    }

    return CalendarRecurrenceRule(
      frequency: rule.frequency.calendarFrequency,
      interval: rule.interval,
      daysOfTheWeek: (rule.daysOfTheWeek ?? []).map {
        CalendarRecurrenceWeekday(
          day: $0.dayOfTheWeek.calendarWeekday,
          weekNumber: $0.weekNumber
        )
      },
      daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
      monthsOfTheYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
      weeksOfTheYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
      daysOfTheYear: (rule.daysOfTheYear ?? []).map(\.intValue),
      setPositions: (rule.setPositions ?? []).map(\.intValue),
      firstDayOfTheWeek: firstDayOfTheWeek,
      end: recurrenceEnd
    )
  }

  private static func makeLocationRecord(
    from location: EKStructuredLocation
  ) -> CalendarStructuredLocationRecord {
    CalendarStructuredLocationRecord(
      title: location.title ?? "",
      latitude: location.geoLocation?.coordinate.latitude,
      longitude: location.geoLocation?.coordinate.longitude,
      radius: location.radius
    )
  }

  private static func makeParticipantRecord(
    from participant: EKParticipant
  ) -> CalendarParticipantRecord {
    CalendarParticipantRecord(
      name: participant.name,
      url: participant.url.absoluteString,
      status: participant.participantStatus.calendarStatus,
      role: participant.participantRole.calendarRole,
      type: participant.participantType.calendarType,
      isCurrentUser: participant.isCurrentUser
    )
  }
}
