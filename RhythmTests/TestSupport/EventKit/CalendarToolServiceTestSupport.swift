import Foundation
import Testing

@testable import Rhythm

@MainActor
func makeCalendarTestCalendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}

@MainActor
func makeCalendarService(
  runtime: EventKitRuntimeSpy,
  now: @escaping () -> Date = { CalendarTestFixtures.start }
) -> CalendarToolService {
  CalendarToolService(
    runtime: runtime,
    calendar: makeCalendarTestCalendar(),
    now: now
  )
}

@MainActor
func requireCalendarTool(
  _ name: String,
  service: CalendarToolService
) throws -> Tool {
  try #require(service.tools().first { $0.name == name })
}
