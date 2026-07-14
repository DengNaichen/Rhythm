import Foundation
import Testing

@testable import Rhythm

@Suite("Calendar recurrence models")
@MainActor
struct CalendarRecurrenceModelsTests {
  @Test("preserves a complete RFC 5545 recurrence shape")
  func completeRule() {
    let end = CalendarTestFixtures.date("2026-12-31T23:59:59Z")
    let rule = CalendarRecurrenceRule(
      frequency: .monthly,
      interval: 2,
      daysOfTheWeek: [
        CalendarRecurrenceWeekday(day: .monday, weekNumber: 1),
        CalendarRecurrenceWeekday(day: .sunday, weekNumber: -1),
      ],
      daysOfTheMonth: [1, -1],
      monthsOfTheYear: [1, 7],
      weeksOfTheYear: [1, -1],
      daysOfTheYear: [1, -1],
      setPositions: [1, -1],
      firstDayOfTheWeek: .monday,
      end: .endDate(end)
    )

    #expect(rule.frequency == .monthly)
    #expect(rule.interval == 2)
    #expect(rule.daysOfTheWeek.first == CalendarRecurrenceWeekday(day: .monday, weekNumber: 1))
    #expect(rule.daysOfTheMonth == [1, -1])
    #expect(rule.monthsOfTheYear == [1, 7])
    #expect(rule.weeksOfTheYear == [1, -1])
    #expect(rule.daysOfTheYear == [1, -1])
    #expect(rule.setPositions == [1, -1])
    #expect(rule.firstDayOfTheWeek == .monday)
    #expect(rule.end == .endDate(end))
  }

  @Test("uses safe recurrence defaults and supports occurrence-count endings")
  func defaultsAndCountEnd() throws {
    let unbounded = CalendarRecurrenceRule(frequency: .daily)
    #expect(unbounded.interval == 1)
    #expect(unbounded.daysOfTheWeek.isEmpty)
    #expect(unbounded.end == nil)

    let bounded = CalendarRecurrenceRule(
      frequency: .weekly,
      end: .occurrenceCount(5)
    )
    #expect(bounded.end == .occurrenceCount(5))

    try CalendarRecurrenceValidator.validate(
      CalendarRecurrenceRule(
        frequency: .daily,
        interval: CalendarRecurrenceRule.maximumInterval
      )
    )
    do {
      try CalendarRecurrenceValidator.validate(
        CalendarRecurrenceRule(
          frequency: .daily,
          interval: CalendarRecurrenceRule.maximumInterval + 1
        )
      )
      Issue.record("Expected recurrence intervals above Int32.max to be rejected")
    } catch {
      #expect(
        error as? CalendarEventRuntimeError
          == .invalidInput(
            argument: "recurrence",
            reason:
              "interval must be between 1 and \(CalendarRecurrenceRule.maximumInterval)"
          )
      )
    }

    do {
      _ = try LiveEventKitRuntime().makeRecurrenceRule(
        from: CalendarRecurrenceRule(
          frequency: .daily,
          daysOfTheWeek: [CalendarRecurrenceWeekday(day: .monday)]
        )
      )
      Issue.record("Expected EventKit-ignored daily selectors to be rejected")
    } catch {
      #expect(
        error as? CalendarEventRuntimeError
          == .invalidInput(
            argument: "recurrence",
            reason: "daily recurrence does not accept BYDAY or numeric selectors"
          )
      )
    }
  }
}
