import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Calendar free-busy use case")
@MainActor
struct CalendarFreeBusyUseCaseTests {
  @Test("merges touching busy windows and reports overlap conflicts")
  func mergedBusyAndConflicts() throws {
    let runtime = EventKitRuntimeSpy()
    let start = CalendarTestFixtures.start
    runtime.events = [
      CalendarTestFixtures.makeEvent(
        id: "event-a",
        startAt: start.addingTimeInterval(30 * 60),
        endAt: start.addingTimeInterval(2 * 60 * 60)
      ),
      CalendarTestFixtures.makeEvent(
        id: "event-b",
        startAt: start.addingTimeInterval(90 * 60),
        endAt: start.addingTimeInterval(3 * 60 * 60)
      ),
      CalendarTestFixtures.makeEvent(
        id: "event-c",
        startAt: start.addingTimeInterval(3 * 60 * 60),
        endAt: start.addingTimeInterval(3.5 * 60 * 60)
      ),
    ]

    let result = try makeUseCase(runtime).execute(arguments: rangeArguments())

    #expect(result.busy.count == 1)
    #expect(result.busy[0].startDate == start.addingTimeInterval(30 * 60))
    #expect(result.busy[0].endDate == start.addingTimeInterval(3.5 * 60 * 60))
    #expect(result.busy[0].events.map(\.id) == ["event-a", "event-b", "event-c"])
    #expect(result.free.count == 2)
    #expect(result.free[0].startDate == start)
    #expect(result.free[0].endDate == start.addingTimeInterval(30 * 60))
    #expect(result.free[1].startDate == start.addingTimeInterval(3.5 * 60 * 60))
    #expect(result.free[1].endDate == start.addingTimeInterval(4 * 60 * 60))
    #expect(result.conflicts.count == 1)
    #expect(result.conflicts[0].startDate == start.addingTimeInterval(90 * 60))
    #expect(result.conflicts[0].endDate == start.addingTimeInterval(2 * 60 * 60))
    #expect(result.conflicts[0].events.map(\.id) == ["event-a", "event-b"])
  }

  @Test("excludes free, canceled, tentative, and all-day events when requested")
  func candidateFilters() throws {
    let runtime = EventKitRuntimeSpy()
    let start = CalendarTestFixtures.start
    runtime.events = [
      CalendarTestFixtures.makeEvent(id: "included"),
      CalendarTestFixtures.makeEvent(id: "free", availability: "free"),
      CalendarTestFixtures.makeEvent(id: "canceled", status: "canceled"),
      CalendarTestFixtures.makeEvent(id: "tentative-status", status: "tentative"),
      CalendarTestFixtures.makeEvent(id: "tentative-availability", availability: "tentative"),
      CalendarTestFixtures.makeEvent(
        id: "all-day",
        startAt: start,
        endAt: start.addingTimeInterval(24 * 60 * 60),
        isAllDay: true
      ),
    ]
    var arguments = rangeArguments()
    arguments["include_all_day"] = .bool(false)
    arguments["include_tentative"] = .bool(false)

    let result = try makeUseCase(runtime).execute(arguments: arguments)

    #expect(result.busy.count == 1)
    #expect(result.busy[0].events.map(\.id) == ["included"])
    #expect(runtime.fetchInputs.last?.includeAllDay == false)
  }

  @Test("clips events to the requested range and forwards strict calendar references")
  func clippingAndReferences() throws {
    let runtime = EventKitRuntimeSpy()
    let start = CalendarTestFixtures.start
    let occurrenceStart = start.addingTimeInterval(-60 * 60)
    let originalStarts = [
      start.addingTimeInterval(-2 * 60 * 60),
      start.addingTimeInterval(-3 * 60 * 60),
    ]
    runtime.events = originalStarts.map { originalStartAt in
      CalendarTestFixtures.makeEvent(
        id: "spanning",
        startAt: occurrenceStart,
        endAt: start.addingTimeInterval(5 * 60 * 60),
        recurrenceRules: [CalendarRecurrenceRule(frequency: .weekly)],
        occurrence: CalendarOccurrenceRecord(
          originalStartAt: originalStartAt,
          isDetached: true
        )
      )
    }
    var arguments = rangeArguments()
    arguments["calendar_ids"] = .array([.string("calendar-work")])
    arguments["list_names"] = .array([.string("Work")])

    let result = try makeUseCase(runtime).execute(arguments: arguments)

    #expect(result.busy.count == 1)
    #expect(result.busy[0].startDate == start)
    #expect(result.busy[0].endDate == start.addingTimeInterval(4 * 60 * 60))
    #expect(result.busy[0].events.count == 2)
    #expect(
      Set(result.busy[0].events.compactMap(\.occurrenceStart))
        == [EventKitDateFormatting.iso8601String(from: occurrenceStart)]
    )
    #expect(
      Set(result.busy[0].events.compactMap(\.originalStartAt))
        == Set(originalStarts.map(EventKitDateFormatting.iso8601String(from:)))
    )
    #expect(result.conflicts.first?.events.count == 2)
    #expect(result.free.isEmpty)
    #expect(
      runtime.fetchInputs.last?.calendars
        == [.id("calendar-work"), .title("Work")]
    )
    #expect(
      runtime.resolutionCalls
        == [
          CalendarResolutionCall(reference: .id("calendar-work"), requireWritable: false),
          CalendarResolutionCall(reference: .title("Work"), requireWritable: false),
        ]
    )
  }

  private func makeUseCase(_ runtime: EventKitRuntimeSpy) -> CalendarFreeBusyUseCase {
    CalendarFreeBusyUseCase(
      runtime: runtime,
      now: { CalendarTestFixtures.start },
      calendar: makeCalendarTestCalendar()
    )
  }

  private func rangeArguments() -> [String: Value] {
    [
      "from": .string("2026-07-14T09:00:00Z"),
      "to": .string("2026-07-14T13:00:00Z"),
    ]
  }
}
