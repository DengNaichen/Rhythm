import Foundation
import Testing

@testable import Rhythm

@Suite("EventKit date range normalization")
@MainActor
struct DateRangeNormalizerTests {
  @Test("defaults Calendar queries to one week from now")
  func defaultCalendarRange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = CalendarTestFixtures.start

    let range = try DateRangeNormalizer.normalizeCalendarRange(
      from: nil,
      to: nil,
      now: { now },
      calendar: calendar
    )

    #expect(range.from == now)
    #expect(range.to == calendar.date(byAdding: .weekOfYear, value: 1, to: now))
  }

  @Test("date-only bounds cover the complete local day")
  func dateOnlyBounds() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
    let day = try #require(
      calendar.date(
        from: DateComponents(
          timeZone: calendar.timeZone,
          year: 2026,
          month: 7,
          day: 14
        )
      )
    )
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))

    let range = try DateRangeNormalizer.normalizeCalendarRange(
      from: "2026-07-14",
      to: "2026-07-14",
      calendar: calendar
    )
    #expect(range == DateRange(from: day, to: nextDay))

    let onlyTo = try DateRangeNormalizer.normalizeCalendarRange(
      from: nil,
      to: "2026-07-14",
      calendar: calendar
    )
    #expect(onlyTo == DateRange(from: day, to: nextDay))
    #expect(calendar.component(.day, from: onlyTo.from) == 14)
  }

  @Test("RFC 3339 offsets normalize to the same instant")
  func rfc3339Offsets() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let utc = try DateRangeNormalizer.normalizeSingleDate(
      "2026-07-14T10:00:00Z",
      argument: "at",
      calendar: calendar
    )
    let offset = try DateRangeNormalizer.normalizeSingleDate(
      "2026-07-14T18:00:00+08:00",
      argument: "at",
      calendar: calendar
    )

    #expect(utc == offset)
  }

  @Test("optional ranges preserve missing bounds and expand date-only values")
  func optionalRange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let day = try #require(
      calendar.date(
        from: DateComponents(
          timeZone: calendar.timeZone,
          year: 2026,
          month: 7,
          day: 14
        )
      )
    )
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))

    let lower = try DateRangeNormalizer.normalizeOptionalRange(
      from: "2026-07-14",
      to: nil,
      calendar: calendar
    )
    #expect(lower == OptionalDateRange(from: day, to: nil))

    let upper = try DateRangeNormalizer.normalizeOptionalRange(
      from: nil,
      to: "2026-07-14",
      calendar: calendar
    )
    #expect(upper == OptionalDateRange(from: nil, to: nextDay))
  }

  @Test("rejects reversed, invalid, and missing single dates")
  func invalidRanges() throws {
    do {
      _ = try DateRangeNormalizer.normalizeCalendarRange(
        from: "2026-07-15T10:00:00Z",
        to: "2026-07-14T10:00:00Z"
      )
      Issue.record("Expected a reversed date range to fail")
    } catch {
      #expect(
        error as? ServiceToolError
          == .invalidValue(
            argument: "to",
            reason: "'to' must be later than or equal to 'from'"
          )
      )
    }

    do {
      _ = try DateRangeNormalizer.normalizeSingleDate("not-a-date", argument: "start_at")
      Issue.record("Expected an invalid date to fail")
    } catch {
      #expect(
        error as? ServiceToolError
          == .invalidDate(argument: "start_at", value: "not-a-date")
      )
    }

    do {
      _ = try DateRangeNormalizer.normalizeSingleDate("  ", argument: "start_at")
      Issue.record("Expected a blank date to fail")
    } catch {
      #expect(error as? ServiceToolError == .missingRequiredArgument("start_at"))
    }
  }
}
