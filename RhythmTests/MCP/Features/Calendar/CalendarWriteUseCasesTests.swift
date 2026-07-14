import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Calendar write use cases")
@MainActor
struct CalendarWriteUseCasesTests {
  @Test("create maps typed destination, alarms, recurrence, and time zone")
  func createRichEvent() async throws {
    let runtime = EventKitRuntimeSpy()
    runtime.createResult = CalendarTestFixtures.makeEvent(id: "event-created")
    let tool = try requireCalendarTool(
      "calendar_events_create",
      service: makeCalendarService(runtime: runtime)
    )

    var arguments = baseCreateArguments()
    arguments["calendar_id"] = .string("calendar-work")
    arguments["notes"] = .string("  Agenda  ")
    arguments["time_zone"] = .string("UTC")
    arguments["availability"] = .string("busy")
    arguments["alarms"] = .array([
      .object([
        "type": .string("relative"),
        "minutes": .int(15),
      ]),
      .object([
        "type": .string("absolute"),
        "at": .string("2026-07-14T08:30:00Z"),
      ]),
      .object([
        "type": .string("proximity"),
        "proximity": .string("leave"),
        "location_title": .string("Office"),
        "latitude": .double(31.2304),
        "longitude": .double(121.4737),
        "radius": .double(250),
      ]),
    ])
    arguments["recurrence"] = .object([
      "frequency": .string("monthly"),
      "interval": .int(2),
      "by_day": .array([.string("1MO"), .string("-1SU")]),
      "occurrence_count": .int(5),
    ])

    let result = try await tool(arguments)

    #expect(runtime.requestAccessCallCount == 1)
    let input = try #require(runtime.createInputs.last)
    #expect(input.calendar == .id("calendar-work"))
    #expect(input.notes == "  Agenda  ")
    #expect(input.timeZoneIdentifier == "UTC")
    #expect(input.availability == .busy)
    #expect(
      input.alarms
        == [
          .relative(minutes: 15, emailAddress: nil),
          .absolute(
            at: CalendarTestFixtures.date("2026-07-14T08:30:00Z"),
            emailAddress: nil
          ),
          .proximity(
            proximity: .leave,
            locationTitle: "Office",
            latitude: 31.2304,
            longitude: 121.4737,
            radius: 250,
            emailAddress: nil
          ),
        ]
    )
    #expect(
      input.recurrenceRules
        == [
          CalendarRecurrenceRule(
            frequency: .monthly,
            interval: 2,
            daysOfTheWeek: [
              CalendarRecurrenceWeekday(day: .monday, weekNumber: 1),
              CalendarRecurrenceWeekday(day: .sunday, weekNumber: -1),
            ],
            end: .occurrenceCount(5)
          )
        ]
    )
    #expect(
      runtime.resolutionCalls.last
        == CalendarResolutionCall(reference: .id("calendar-work"), requireWritable: true)
    )
    #expect(result.objectValue?["id"] == .string("event-created"))
  }

  @Test("update maps null-clears and recurring span, rejecting unsafe future spans")
  func updatePatchAndSpan() async throws {
    let recurrence = CalendarRecurrenceRule(frequency: .weekly)
    let occurrence = CalendarOccurrenceRecord(
      originalStartAt: CalendarTestFixtures.originalStartAt,
      isDetached: true
    )
    let recurring = CalendarTestFixtures.makeEvent(
      startAt: CalendarTestFixtures.occurrenceStart,
      endAt: CalendarTestFixtures.occurrenceStart.addingTimeInterval(3_600),
      recurrenceRules: [recurrence],
      occurrence: occurrence
    )
    let runtime = EventKitRuntimeSpy()
    runtime.events = [recurring]
    runtime.updateResult = recurring
    let tool = try requireCalendarTool(
      "calendar_events_update",
      service: makeCalendarService(runtime: runtime)
    )

    _ = try await tool([
      "id": .string("event-1"),
      "occurrence_start": .string("2026-07-21T10:00:00Z"),
      "original_start_at": .string("2026-07-21T09:00:00Z"),
      "span": .string("future_events"),
      "calendar_id": .string("calendar-work"),
      "title": .string("Updated planning"),
      "location": .null,
      "notes": .string("  Keep spacing  "),
      "url": .null,
      "time_zone": .null,
      "alarms": .null,
      "recurrence": .null,
    ])

    let call = try #require(runtime.updateCalls.last)
    #expect(call.reference == recurring.reference)
    #expect(call.span == .futureEvents)
    #expect(call.input.calendar == .id("calendar-work"))
    #expect(call.input.location == .clear)
    #expect(call.input.notes == .set("  Keep spacing  "))
    #expect(call.input.url == .clear)
    #expect(call.input.timeZoneIdentifier == .clear)
    #expect(call.input.alarms == [])
    #expect(call.input.recurrenceRules == [])

    let partialReferenceRuntime = EventKitRuntimeSpy()
    partialReferenceRuntime.events = [recurring]
    let partialReferenceTool = try requireCalendarTool(
      "calendar_events_update",
      service: makeCalendarService(runtime: partialReferenceRuntime)
    )
    for (arguments, missingField): ([String: Value], String) in [
      (
        [
          "id": .string("event-1"),
          "occurrence_start": .string("2026-07-21T10:00:00Z"),
          "title": .string("Unsafe"),
        ],
        "original_start_at"
      ),
      (
        [
          "id": .string("event-1"),
          "original_start_at": .string("2026-07-21T09:00:00Z"),
          "title": .string("Unsafe"),
        ],
        "occurrence_start"
      ),
    ] {
      do {
        _ = try await partialReferenceTool(arguments)
        Issue.record("Expected recurring writes to require both occurrence reference fields")
      } catch {
        #expect(error.localizedDescription.contains(missingField))
      }
    }
    #expect(partialReferenceRuntime.updateCalls.isEmpty)

    let plainRuntime = EventKitRuntimeSpy()
    let plainTool = try requireCalendarTool(
      "calendar_events_update",
      service: makeCalendarService(runtime: plainRuntime)
    )
    do {
      _ = try await plainTool([
        "id": .string("event-1"),
        "span": .string("future_events"),
        "title": .string("Unsafe"),
      ])
      Issue.record("Expected future_events to require a recurring event")
    } catch {
      #expect(error.localizedDescription.contains("recurring event"))
    }
    #expect(plainRuntime.updateCalls.isEmpty)
  }

  @Test("delete requires confirmation and preserves occurrence span")
  func deleteConfirmationAndSpan() async throws {
    let runtime = EventKitRuntimeSpy()
    let tool = try requireCalendarTool(
      "calendar_events_delete",
      service: makeCalendarService(runtime: runtime)
    )

    for arguments: [String: Value] in [
      ["id": .string("event-1")],
      ["id": .string("event-1"), "confirm": .bool(false)],
    ] {
      do {
        _ = try await tool(arguments)
        Issue.record("Expected delete confirmation to be required")
      } catch {
        #expect(error.localizedDescription.contains("confirm"))
      }
    }
    #expect(runtime.requestAccessCallCount == 0)
    #expect(runtime.deleteCalls.isEmpty)

    let recurring = CalendarTestFixtures.makeEvent(
      startAt: CalendarTestFixtures.occurrenceStart,
      endAt: CalendarTestFixtures.occurrenceStart.addingTimeInterval(3_600),
      recurrenceRules: [CalendarRecurrenceRule(frequency: .weekly)],
      occurrence: CalendarOccurrenceRecord(
        originalStartAt: CalendarTestFixtures.originalStartAt,
        isDetached: true
      )
    )
    runtime.events = [recurring]
    runtime.deleteResult = recurring

    for (reference, missingField): ([String: Value], String) in [
      (
        ["occurrence_start": .string("2026-07-21T10:00:00Z")],
        "original_start_at"
      ),
      (
        ["original_start_at": .string("2026-07-21T09:00:00Z")],
        "occurrence_start"
      ),
    ] {
      var arguments = reference
      arguments["id"] = .string("event-1")
      arguments["confirm"] = .bool(true)
      do {
        _ = try await tool(arguments)
        Issue.record("Expected recurring deletes to require both occurrence reference fields")
      } catch {
        #expect(error.localizedDescription.contains(missingField))
      }
    }
    #expect(runtime.deleteCalls.isEmpty)

    let result = try await tool([
      "id": .string("event-1"),
      "occurrence_start": .string("2026-07-21T10:00:00Z"),
      "original_start_at": .string("2026-07-21T09:00:00Z"),
      "span": .string("future_events"),
      "confirm": .bool(true),
    ])

    #expect(
      runtime.deleteCalls
        == [
          CalendarDeleteCall(reference: recurring.reference, span: .futureEvents)
        ]
    )
    #expect(result.objectValue?["deleted"] == .bool(true))
    #expect(result.objectValue?["span"] == .string("future_events"))
    #expect(
      result.objectValue?["occurrence_start"]
        == .string("2026-07-21T10:00:00.000Z")
    )
    #expect(
      result.objectValue?["original_start_at"]
        == .string("2026-07-21T09:00:00.000Z")
    )
  }

  @Test("rejects invalid alarm and recurrence combinations before creation")
  func invalidAlarmAndRecurrence() async throws {
    var invalidArguments: [[String: Value]] = []

    let boundaryRuntime = EventKitRuntimeSpy()
    let boundaryTool = try requireCalendarTool(
      "calendar_events_create",
      service: makeCalendarService(runtime: boundaryRuntime)
    )
    var boundaryArguments = baseCreateArguments()
    boundaryArguments["alarms"] = .array([
      .object([
        "type": .string("relative"),
        "minutes": .int(CalendarAlarmInput.maximumRelativeMinutes),
      ])
    ])
    boundaryArguments["recurrence"] = .object([
      "frequency": .string("daily"),
      "interval": .int(CalendarRecurrenceRule.maximumInterval),
    ])
    _ = try await boundaryTool(boundaryArguments)
    #expect(
      boundaryRuntime.createInputs.last?.alarms
        == [
          .relative(
            minutes: CalendarAlarmInput.maximumRelativeMinutes,
            emailAddress: nil
          )
        ]
    )
    #expect(
      boundaryRuntime.createInputs.last?.recurrenceRules.first?.interval
        == CalendarRecurrenceRule.maximumInterval
    )

    var relativeWithAbsolute = baseCreateArguments()
    relativeWithAbsolute["alarms"] = .array([
      .object([
        "type": .string("relative"),
        "minutes": .int(10),
        "at": .string("2026-07-14T08:30:00Z"),
      ])
    ])
    invalidArguments.append(relativeWithAbsolute)

    var alarmOverflow = baseCreateArguments()
    alarmOverflow["alarms"] = .array([
      .object([
        "type": .string("relative"),
        "minutes": .int(CalendarAlarmInput.maximumRelativeMinutes + 1),
      ])
    ])

    var conflictingEnd = baseCreateArguments()
    conflictingEnd["recurrence"] = .object([
      "frequency": .string("weekly"),
      "end_at": .string("2026-08-01T09:00:00Z"),
      "occurrence_count": .int(5),
    ])
    invalidArguments.append(conflictingEnd)

    var intervalOverflow = baseCreateArguments()
    intervalOverflow["recurrence"] = .object([
      "frequency": .string("daily"),
      "interval": .int(CalendarRecurrenceRule.maximumInterval + 1),
    ])

    let overflowCases: [([String: Value], ServiceToolError)] = [
      (
        alarmOverflow,
        .invalidValue(
          argument: "alarms[0]",
          reason: "must match exactly one allowed schema"
        )
      ),
      (
        intervalOverflow,
        .invalidValue(
          argument: "recurrence.interval",
          reason: "must be at most \(CalendarRecurrenceRule.maximumInterval)"
        )
      ),
    ]
    for (arguments, expectedError) in overflowCases {
      let runtime = EventKitRuntimeSpy()
      let tool = try requireCalendarTool(
        "calendar_events_create",
        service: makeCalendarService(runtime: runtime)
      )
      do {
        _ = try await tool(arguments)
        Issue.record("Expected overflowing Calendar integers to fail")
      } catch {
        #expect(error as? ServiceToolError == expectedError)
      }
      #expect(runtime.createInputs.isEmpty)
    }

    var badWeekday = baseCreateArguments()
    badWeekday["recurrence"] = .object([
      "frequency": .string("monthly"),
      "by_day": .array([.string("0MO")]),
    ])
    invalidArguments.append(badWeekday)

    var earlyEnd = baseCreateArguments()
    earlyEnd["recurrence"] = .object([
      "frequency": .string("weekly"),
      "end_at": .string("2026-07-13T09:00:00Z"),
    ])
    invalidArguments.append(earlyEnd)

    var sameDayAllDay = baseCreateArguments()
    sameDayAllDay["start_at"] = .string("2026-07-14")
    sameDayAllDay["end_at"] = .string("2026-07-14")
    sameDayAllDay["is_all_day"] = .bool(true)
    invalidArguments.append(sameDayAllDay)

    var ignoredDailySelector = baseCreateArguments()
    ignoredDailySelector["recurrence"] = .object([
      "frequency": .string("daily"),
      "by_day": .array([.string("MO")]),
    ])
    invalidArguments.append(ignoredDailySelector)

    for arguments in invalidArguments {
      let runtime = EventKitRuntimeSpy()
      let tool = try requireCalendarTool(
        "calendar_events_create",
        service: makeCalendarService(runtime: runtime)
      )
      do {
        _ = try await tool(arguments)
        Issue.record("Expected invalid Calendar input to fail")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
      #expect(runtime.createInputs.isEmpty)
    }
  }

  @Test("rejects conflicting references, invalid zones, and unknown schema fields")
  func strictWriteInputs() async throws {
    var conflictingReference = baseCreateArguments()
    conflictingReference["calendar_id"] = .string("calendar-work")
    conflictingReference["list_name"] = .string("Work")

    var invalidTimeZone = baseCreateArguments()
    invalidTimeZone["time_zone"] = .string("Mars/Olympus_Mons")

    var blankCalendarID = baseCreateArguments()
    blankCalendarID["calendar_id"] = .string("  ")

    var unknownRoot = baseCreateArguments()
    unknownRoot["typo"] = .bool(true)

    var unknownNested = baseCreateArguments()
    unknownNested["alarms"] = .array([
      .object([
        "type": .string("relative"),
        "minutes": .int(15),
        "typo": .bool(true),
      ])
    ])

    for arguments in [
      conflictingReference,
      invalidTimeZone,
      blankCalendarID,
      unknownRoot,
      unknownNested,
    ] {
      let runtime = EventKitRuntimeSpy()
      let tool = try requireCalendarTool(
        "calendar_events_create",
        service: makeCalendarService(runtime: runtime)
      )
      do {
        _ = try await tool(arguments)
        Issue.record("Expected strict Calendar input validation to fail")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
      #expect(runtime.createInputs.isEmpty)
    }

    let updateRuntime = EventKitRuntimeSpy()
    let updateTool = try requireCalendarTool(
      "calendar_events_update",
      service: makeCalendarService(runtime: updateRuntime)
    )
    do {
      _ = try await updateTool([
        "id": .string("event-1"),
        "title": .string("Updated"),
        "calendar_id": .string("  "),
      ])
      Issue.record("Expected a blank update calendar ID to fail")
    } catch {
      #expect(!error.localizedDescription.isEmpty)
    }
    #expect(updateRuntime.updateCalls.isEmpty)
  }

  private func baseCreateArguments() -> [String: Value] {
    [
      "title": .string("Planning"),
      "start_at": .string("2026-07-14T09:00:00Z"),
      "end_at": .string("2026-07-14T10:00:00Z"),
    ]
  }
}
