import Foundation

nonisolated enum CalendarAlarmKind: String, CaseIterable, Sendable {
  case relative
  case absolute
  case proximity
}

nonisolated enum CalendarAlarmAction: String, Sendable {
  case display
  case audio
  case procedure
  case email
  case unknown
}

nonisolated enum AlarmProximityKind: String, CaseIterable, Sendable {
  case enter
  case leave
}

nonisolated enum CalendarAlarmInput: Equatable, Sendable {
  static let maximumRelativeMinutes = 525_600

  case relative(minutes: Int, emailAddress: String?)
  case absolute(at: Date, emailAddress: String?)
  case proximity(
    proximity: AlarmProximityKind,
    locationTitle: String,
    latitude: Double,
    longitude: Double,
    radius: Double,
    emailAddress: String?
  )
}

nonisolated struct CalendarAlarmRecord: Equatable, Sendable {
  let kind: CalendarAlarmKind
  let relativeOffsetMinutes: Double?
  let absoluteAt: Date?
  let proximity: AlarmProximityKind?
  let locationTitle: String?
  let latitude: Double?
  let longitude: Double?
  let radius: Double?
  let action: CalendarAlarmAction
  let emailAddress: String?
  let soundName: String?
}
