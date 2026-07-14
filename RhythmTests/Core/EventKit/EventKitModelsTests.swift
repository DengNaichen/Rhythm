import Foundation
import Testing

@testable import Rhythm

@Suite("EventKit shared models")
@MainActor
struct EventKitModelsTests {
  @Test("calendar references retain explicit identity kind")
  func calendarReferenceKinds() {
    #expect(EventKitCalendarReference.id("calendar-1").kind == "id")
    #expect(EventKitCalendarReference.id("calendar-1").value == "calendar-1")
    #expect(EventKitCalendarReference.title("Work").kind == "title")
    #expect(EventKitCalendarReference.title("Work").value == "Work")
  }

  @Test("runtime errors expose actionable reference diagnostics")
  func runtimeErrorDescriptions() {
    let ambiguous = CalendarEventRuntimeError.ambiguousCalendarTitle(
      title: "Team",
      matchingIDs: ["calendar-team-a", "calendar-team-b"]
    )
    #expect(
      ambiguous.localizedDescription
        == "Calendar title 'Team' is ambiguous; matching IDs: calendar-team-a, calendar-team-b."
    )

    let reference = CalendarEventReference(
      id: "event-1",
      occurrenceStart: CalendarTestFixtures.occurrenceStart,
      originalStartAt: CalendarTestFixtures.originalStartAt
    )
    let occurrenceStart = EventKitDateFormatting.iso8601String(
      from: CalendarTestFixtures.occurrenceStart
    )
    let originalStartAt = EventKitDateFormatting.iso8601String(
      from: CalendarTestFixtures.originalStartAt
    )
    #expect(
      CalendarEventRuntimeError.eventNotFound(reference).localizedDescription
        == "Event 'event-1' occurrence (start \(occurrenceStart), original start \(originalStartAt)) was not found."
    )
  }
}
