import EventKit
import Foundation

@MainActor
final class CalendarToolService: Service {
  let id = "calendar"
  let displayName = "Calendar"

  let runtime: EventKitRuntime
  let calendar: Calendar
  let now: () -> Date

  init(
    runtime: EventKitRuntime,
    calendar: Calendar = .eventKitGregorian,
    now: @escaping () -> Date = { Date() }
  ) {
    self.runtime = runtime
    self.calendar = calendar
    self.now = now
  }

  convenience init(
    calendar: Calendar = .eventKitGregorian,
    now: @escaping () -> Date = { Date() }
  ) {
    self.init(runtime: LiveEventKitRuntime(calendar: calendar), calendar: calendar, now: now)
  }

  func tools() -> [Tool] {
    [
      listCalendarsTool(),
      fetchEventsTool(),
      getEventTool(),
      createEventTool(),
      updateEventTool(),
      deleteEventTool(),
      freeBusyTool(),
    ]
  }

  func isActivated() async -> Bool {
    runtime.eventAuthorizationStatus() == .fullAccess
  }

  func activate() async throws {
    try await runtime.requestEventAccess()
  }

  func authorizationState() -> CalendarAuthorizationState {
    switch runtime.eventAuthorizationStatus() {
    case .fullAccess:
      return .granted
    case .notDetermined:
      return .notDetermined
    case .restricted, .denied, .writeOnly:
      return .denied
    @unknown default:
      return .denied
    }
  }

  func requestAccess() async throws -> CalendarAuthorizationState {
    if runtime.eventAuthorizationStatus() == .writeOnly {
      try await runtime.requestEventAccess()
      return authorizationState()
    }
    switch authorizationState() {
    case .granted:
      return .granted
    case .denied:
      return .denied
    case .notDetermined:
      try await runtime.requestEventAccess()
      return authorizationState()
    }
  }

  func fetchUpcomingEvents(referenceDate: Date, daysAhead: Int) -> [CalendarEventRecord] {
    guard authorizationState() == .granted else { return [] }

    let startDate = calendar.startOfDay(for: referenceDate)
    let endDate =
      calendar.date(byAdding: .day, value: max(daysAhead, 1), to: startDate)
      ?? startDate

    do {
      return try runtime.fetchEvents(
        CalendarEventsFetchInput(
          range: DateRange(from: startDate, to: endDate),
          calendars: nil
        )
      )
      .sorted { $0.startAt < $1.startAt }
    } catch {
      return []
    }
  }
}
