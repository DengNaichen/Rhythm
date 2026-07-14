import Foundation
import Testing

@testable import Rhythm

@Suite("Calendar event models")
@MainActor
struct CalendarEventModelsTests {
  @Test("derives alarm, recurrence, occurrence, and reference metadata")
  func derivedMetadata() {
    let alarm = CalendarAlarmRecord(
      kind: .relative,
      relativeOffsetMinutes: -15,
      absoluteAt: nil,
      proximity: nil,
      locationTitle: nil,
      latitude: nil,
      longitude: nil,
      radius: nil,
      action: .display,
      emailAddress: nil,
      soundName: nil
    )
    let recurrence = CalendarRecurrenceRule(
      frequency: .weekly,
      daysOfTheWeek: [CalendarRecurrenceWeekday(day: .tuesday)]
    )
    let occurrence = CalendarOccurrenceRecord(
      originalStartAt: CalendarTestFixtures.originalStartAt,
      isDetached: true
    )
    let event = CalendarTestFixtures.makeEvent(
      startAt: CalendarTestFixtures.occurrenceStart,
      endAt: CalendarTestFixtures.occurrenceStart.addingTimeInterval(3_600),
      alarms: [alarm],
      recurrenceRules: [recurrence],
      occurrence: occurrence
    )

    #expect(event.hasAlarms)
    #expect(event.isRecurring)
    #expect(event.listTitle == CalendarTestFixtures.writableCalendar.title)
    #expect(event.occurrenceStart == CalendarTestFixtures.occurrenceStart)
    #expect(event.originalStartAt == CalendarTestFixtures.originalStartAt)
    #expect(event.isDetached)
    #expect(
      event.reference
        == CalendarEventReference(
          id: event.id,
          occurrenceStart: CalendarTestFixtures.occurrenceStart,
          originalStartAt: CalendarTestFixtures.originalStartAt
        )
    )
  }

  @Test("plain events do not report recurrence or alarms")
  func plainEventMetadata() {
    let event = CalendarTestFixtures.event

    #expect(!event.hasAlarms)
    #expect(!event.isRecurring)
    #expect(event.occurrenceStart == nil)
    #expect(event.originalStartAt == nil)
    #expect(!event.isDetached)
    #expect(event.reference == CalendarEventReference(id: event.id))
  }

  @Test("update models distinguish unchanged, replacement, and clear operations")
  func updatePatchSemantics() {
    let input = CalendarEventUpdateInput(
      title: "Updated",
      location: .clear,
      notes: .set("Preserved whitespace  "),
      url: .unchanged,
      timeZoneIdentifier: .set("Asia/Shanghai"),
      alarms: [],
      recurrenceRules: []
    )

    #expect(input.title == "Updated")
    #expect(input.location == .clear)
    #expect(input.notes == .set("Preserved whitespace  "))
    #expect(input.url == .unchanged)
    #expect(input.timeZoneIdentifier == .set("Asia/Shanghai"))
    #expect(input.alarms == [])
    #expect(input.recurrenceRules == [])
  }
}
