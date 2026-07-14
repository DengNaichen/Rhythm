import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Calendar read use cases")
@MainActor
struct CalendarReadUseCasesTests {
  @Test("fetch maps typed references and filters, then sorts deterministically")
  func fetchMappingAndSorting() throws {
    let runtime = EventKitRuntimeSpy()
    runtime.events = [
      CalendarTestFixtures.makeEvent(
        id: "event-z",
        startAt: CalendarTestFixtures.start.addingTimeInterval(3_600),
        endAt: CalendarTestFixtures.end.addingTimeInterval(3_600)
      ),
      CalendarTestFixtures.makeEvent(id: "event-b"),
      CalendarTestFixtures.makeEvent(id: "event-a"),
    ]
    let useCase = CalendarEventsFetchUseCase(
      runtime: runtime,
      now: { CalendarTestFixtures.start },
      calendar: makeCalendarTestCalendar()
    )

    let result = try useCase.execute(arguments: [
      "from": .string("2026-07-14T08:00:00Z"),
      "to": .string("2026-07-14T13:00:00Z"),
      "calendar_ids": .array([.string("calendar-work")]),
      "list_names": .array([.string("Work")]),
      "query": .string("plan"),
      "include_all_day": .bool(false),
      "status": .string("confirmed"),
      "availability": .string("busy"),
      "has_alarms": .bool(true),
      "is_recurring": .bool(false),
    ])

    #expect(result.map(\.id) == ["event-a", "event-b", "event-z"])
    let input = try #require(runtime.fetchInputs.last)
    #expect(
      input.calendars
        == [.id("calendar-work"), .title("Work")]
    )
    #expect(input.query == "plan")
    #expect(!input.includeAllDay)
    #expect(input.status == .confirmed)
    #expect(input.availability == .busy)
    #expect(input.hasAlarms == true)
    #expect(input.isRecurring == false)
    #expect(
      runtime.resolutionCalls
        == [
          CalendarResolutionCall(reference: .id("calendar-work"), requireWritable: false),
          CalendarResolutionCall(reference: .title("Work"), requireWritable: false),
        ]
    )
  }

  @Test("get forwards a recurring occurrence reference")
  func getOccurrence() throws {
    let runtime = EventKitRuntimeSpy()
    let occurrence = CalendarOccurrenceRecord(
      originalStartAt: CalendarTestFixtures.originalStartAt,
      isDetached: true
    )
    runtime.events = [
      CalendarTestFixtures.makeEvent(
        startAt: CalendarTestFixtures.occurrenceStart,
        endAt: CalendarTestFixtures.occurrenceStart.addingTimeInterval(3_600),
        occurrence: occurrence
      )
    ]

    let useCase = CalendarEventGetUseCase(
      runtime: runtime,
      calendar: makeCalendarTestCalendar()
    )
    let result = try useCase.execute(arguments: [
      "id": .string("event-1"),
      "occurrence_start": .string("2026-07-21T10:00:00Z"),
      "original_start_at": .string("2026-07-21T09:00:00Z"),
    ])

    #expect(
      runtime.eventReferences
        == [
          CalendarEventReference(
            id: "event-1",
            occurrenceStart: CalendarTestFixtures.occurrenceStart,
            originalStartAt: CalendarTestFixtures.originalStartAt
          )
        ]
    )
    #expect(result.id == "event-1")
    #expect(result.occurrenceStart == "2026-07-21T10:00:00.000Z")
    #expect(result.originalStartAt == "2026-07-21T09:00:00.000Z")
    #expect(result.isDetached)

    let legacyResult = try useCase.execute(arguments: [
      "id": .string("event-1"),
      "occurrence_start": .string("2026-07-21T09:00:00Z"),
    ])
    #expect(
      runtime.eventReferences.last
        == CalendarEventReference(
          id: "event-1",
          occurrenceStart: CalendarTestFixtures.originalStartAt
        )
    )
    #expect(legacyResult.occurrenceStart == "2026-07-21T10:00:00.000Z")
    #expect(legacyResult.originalStartAt == "2026-07-21T09:00:00.000Z")
  }

  @Test("the runtime rejects ambiguous titles and blank calendar-array references")
  func strictCalendarReferences() throws {
    let runtime = EventKitRuntimeSpy()
    runtime.calendars = CalendarTestFixtures.duplicateTitleCalendars
    let useCase = CalendarEventsFetchUseCase(
      runtime: runtime,
      now: { CalendarTestFixtures.start },
      calendar: makeCalendarTestCalendar()
    )

    do {
      _ = try useCase.execute(arguments: [
        "from": .string("2026-07-14T08:00:00Z"),
        "to": .string("2026-07-14T13:00:00Z"),
        "list_names": .array([.string("Team")]),
      ])
      Issue.record("Expected an ambiguous title to fail")
    } catch {
      #expect(
        error as? CalendarEventRuntimeError
          == .ambiguousCalendarTitle(
            title: "Team",
            matchingIDs: ["calendar-team-a", "calendar-team-b"]
          )
      )
    }

    for arguments: [String: Value] in [
      ["calendar_ids": .array([.string("calendar-work"), .string("  ")])],
      ["list_names": .array([.string("Work"), .string("  ")])],
    ] {
      let strictRuntime = EventKitRuntimeSpy()
      let strictUseCase = CalendarEventsFetchUseCase(
        runtime: strictRuntime,
        now: { CalendarTestFixtures.start },
        calendar: makeCalendarTestCalendar()
      )
      do {
        _ = try strictUseCase.execute(arguments: arguments)
        Issue.record("Expected every calendar array reference to be non-blank")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
      #expect(strictRuntime.fetchInputs.isEmpty)
    }
  }
}
