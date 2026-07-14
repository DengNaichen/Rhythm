import CoreLocation
import EventKit
import Foundation

extension LiveEventKitRuntime {
  func makeEventAlarm(from input: CalendarAlarmInput) throws -> EKAlarm {
    switch input {
    case .relative(let minutes, let emailAddress):
      guard (0...CalendarAlarmInput.maximumRelativeMinutes).contains(minutes) else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "alarms.minutes",
          reason:
            "minutes before the event must be between 0 and \(CalendarAlarmInput.maximumRelativeMinutes)"
        )
      }
      let alarm = EKAlarm(relativeOffset: -TimeInterval(minutes) * 60)
      applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
      return alarm

    case .absolute(let date, let emailAddress):
      let alarm = EKAlarm(absoluteDate: date)
      applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
      return alarm

    case .proximity(
      let proximity,
      let locationTitle,
      let latitude,
      let longitude,
      let radius,
      let emailAddress
    ):
      let title = locationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "alarms.location_title",
          reason: "location title must not be empty"
        )
      }
      guard (-90...90).contains(latitude) else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "alarms.latitude",
          reason: "latitude must be between -90 and 90"
        )
      }
      guard (-180...180).contains(longitude) else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "alarms.longitude",
          reason: "longitude must be between -180 and 180"
        )
      }
      guard radius > 0 else {
        throw CalendarEventRuntimeError.invalidInput(
          argument: "alarms.radius",
          reason: "radius must be greater than zero"
        )
      }

      let alarm = EKAlarm()
      alarm.proximity = proximity == .enter ? .enter : .leave
      let structuredLocation = EKStructuredLocation(title: title)
      structuredLocation.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
      structuredLocation.radius = radius
      alarm.structuredLocation = structuredLocation
      applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
      return alarm
    }
  }

  func makeRecurrenceRule(from input: CalendarRecurrenceRule) throws -> EKRecurrenceRule {
    try CalendarRecurrenceValidator.validate(input)

    let end: EKRecurrenceEnd?
    switch input.end {
    case .occurrenceCount(let count):
      end = EKRecurrenceEnd(occurrenceCount: count)
    case .endDate(let date):
      end = EKRecurrenceEnd(end: date)
    case nil:
      end = nil
    }

    let weekdays = input.daysOfTheWeek.map {
      EKRecurrenceDayOfWeek($0.day.eventKitWeekday, weekNumber: $0.weekNumber)
    }

    return EKRecurrenceRule(
      recurrenceWith: input.frequency.eventKitFrequency,
      interval: input.interval,
      daysOfTheWeek: weekdays.nilIfEmpty,
      daysOfTheMonth: input.daysOfTheMonth.map(NSNumber.init(value:)).nilIfEmpty,
      monthsOfTheYear: input.monthsOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      weeksOfTheYear: input.weeksOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      daysOfTheYear: input.daysOfTheYear.map(NSNumber.init(value:)).nilIfEmpty,
      setPositions: input.setPositions.map(NSNumber.init(value:)).nilIfEmpty,
      end: end
    )
  }

  private func applyAlarmMetadata(emailAddress: String?, to alarm: EKAlarm) {
    if let emailAddress = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
      !emailAddress.isEmpty
    {
      alarm.emailAddress = emailAddress
    }
  }

}

extension Array {
  fileprivate var nilIfEmpty: Self? { isEmpty ? nil : self }
}
