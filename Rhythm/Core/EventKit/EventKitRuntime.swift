import EventKit
import Foundation

@MainActor
protocol EventKitRuntime: AnyObject {
  func eventAuthorizationStatus() -> EKAuthorizationStatus
  func requestEventAccess() async throws

  func listEventCalendars() -> [EventKitListRecord]
  func resolveEventCalendar(
    _ reference: EventKitCalendarReference,
    requireWritable: Bool
  ) throws -> EventKitListRecord

  func fetchEvents(_ input: CalendarEventsFetchInput) throws -> [CalendarEventRecord]
  func event(_ reference: CalendarEventReference) throws -> CalendarEventRecord
  func createEvent(_ input: CalendarEventCreateInput) throws -> CalendarEventRecord
  func updateEvent(
    _ reference: CalendarEventReference,
    input: CalendarEventUpdateInput,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord
  func deleteEvent(
    _ reference: CalendarEventReference,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord
}

@MainActor
final class LiveEventKitRuntime: EventKitRuntime {
  let eventStore: EKEventStore
  let calendar: Calendar

  init(
    eventStore: EKEventStore = EKEventStore(),
    calendar: Calendar = .eventKitGregorian
  ) {
    self.eventStore = eventStore
    self.calendar = calendar
  }

  func eventAuthorizationStatus() -> EKAuthorizationStatus {
    EKEventStore.authorizationStatus(for: .event)
  }

  func requestEventAccess() async throws {
    try await eventStore.requestFullAccessToEvents()
  }

  func listEventCalendars() -> [EventKitListRecord] {
    eventStore.calendars(for: .event)
      .map(Self.makeListRecord(from:))
      .sorted {
        if $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedSame {
          return $0.id < $1.id
        }
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
  }

  func resolveEventCalendar(
    _ reference: EventKitCalendarReference,
    requireWritable: Bool = false
  ) throws -> EventKitListRecord {
    Self.makeListRecord(
      from: try resolveCalendar(reference, requireWritable: requireWritable)
    )
  }
}
