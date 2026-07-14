import Foundation
import Testing

@testable import Rhythm

@Suite("Things date-time input")
@MainActor
struct ThingsDateTimeInputTests {
  @Test("normalizes RFC3339 offsets while preserving local date-time input")
  func dateTimeInputNormalization() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let utc = try #require(
      ThingsDateTimeInput.timestamp(
        "2026-07-13T10:00:00Z", upperBound: false, calendar: calendar))
    let offset = try #require(
      ThingsDateTimeInput.timestamp(
        "2026-07-13T18:00:00+08:00", upperBound: false, calendar: calendar))
    let local = try #require(
      ThingsDateTimeInput.timestamp(
        "2026-07-13T10:00", upperBound: false, calendar: calendar))

    #expect(utc == offset)
    #expect(utc == local)
    #expect(
      ThingsDateTimeInput.localTimestamp(utc, calendar: calendar, separator: " ")
        == "2026-07-13 10:00:00"
    )
  }
}
