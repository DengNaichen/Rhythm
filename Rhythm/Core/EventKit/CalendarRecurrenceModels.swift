import Foundation

nonisolated enum CalendarRecurrenceFrequency: String, CaseIterable, Sendable {
  case daily
  case weekly
  case monthly
  case yearly
}

nonisolated enum CalendarWeekday: String, CaseIterable, Sendable {
  case sunday
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
}

nonisolated struct CalendarRecurrenceWeekday: Equatable, Hashable, Sendable {
  let day: CalendarWeekday
  let weekNumber: Int

  init(day: CalendarWeekday, weekNumber: Int = 0) {
    self.day = day
    self.weekNumber = weekNumber
  }
}

nonisolated enum CalendarRecurrenceEnd: Equatable, Sendable {
  case occurrenceCount(Int)
  case endDate(Date)
}

nonisolated struct CalendarRecurrenceRule: Equatable, Sendable {
  static let maximumInterval = Int(Int32.max)

  let frequency: CalendarRecurrenceFrequency
  let interval: Int
  let daysOfTheWeek: [CalendarRecurrenceWeekday]
  let daysOfTheMonth: [Int]
  let monthsOfTheYear: [Int]
  let weeksOfTheYear: [Int]
  let daysOfTheYear: [Int]
  let setPositions: [Int]
  let firstDayOfTheWeek: CalendarWeekday?
  let end: CalendarRecurrenceEnd?

  init(
    frequency: CalendarRecurrenceFrequency,
    interval: Int = 1,
    daysOfTheWeek: [CalendarRecurrenceWeekday] = [],
    daysOfTheMonth: [Int] = [],
    monthsOfTheYear: [Int] = [],
    weeksOfTheYear: [Int] = [],
    daysOfTheYear: [Int] = [],
    setPositions: [Int] = [],
    firstDayOfTheWeek: CalendarWeekday? = nil,
    end: CalendarRecurrenceEnd? = nil
  ) {
    self.frequency = frequency
    self.interval = interval
    self.daysOfTheWeek = daysOfTheWeek
    self.daysOfTheMonth = daysOfTheMonth
    self.monthsOfTheYear = monthsOfTheYear
    self.weeksOfTheYear = weeksOfTheYear
    self.daysOfTheYear = daysOfTheYear
    self.setPositions = setPositions
    self.firstDayOfTheWeek = firstDayOfTheWeek
    self.end = end
  }
}

nonisolated enum CalendarRecurrenceValidator {
  static func validate(_ rule: CalendarRecurrenceRule) throws {
    guard (1...CalendarRecurrenceRule.maximumInterval).contains(rule.interval) else {
      throw recurrenceError(
        "interval must be between 1 and \(CalendarRecurrenceRule.maximumInterval)"
      )
    }
    guard rule.firstDayOfTheWeek == nil else {
      throw recurrenceError("first_day_of_week is read-only in EventKit")
    }

    try validateUnique(rule.daysOfTheWeek, field: "days_of_the_week")
    try validateNumbers(rule.daysOfTheMonth, absoluteRange: 1...31, field: "days_of_the_month")
    try validatePositiveNumbers(rule.monthsOfTheYear, range: 1...12, field: "months_of_the_year")
    try validateNumbers(rule.weeksOfTheYear, absoluteRange: 1...53, field: "weeks_of_the_year")
    try validateNumbers(rule.daysOfTheYear, absoluteRange: 1...366, field: "days_of_the_year")
    try validateNumbers(rule.setPositions, absoluteRange: 1...366, field: "set_positions")

    if case .occurrenceCount(let count) = rule.end, count <= 0 {
      throw recurrenceError("occurrence_count must be greater than zero")
    }

    switch rule.frequency {
    case .daily:
      guard rule.daysOfTheWeek.isEmpty, rule.daysOfTheMonth.isEmpty,
        rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
        rule.daysOfTheYear.isEmpty, rule.setPositions.isEmpty
      else {
        throw recurrenceError("daily recurrence does not accept BYDAY or numeric selectors")
      }

    case .weekly:
      guard rule.daysOfTheMonth.isEmpty, rule.monthsOfTheYear.isEmpty,
        rule.weeksOfTheYear.isEmpty, rule.daysOfTheYear.isEmpty
      else {
        throw recurrenceError("weekly recurrence only accepts days_of_the_week and set_positions")
      }
      guard rule.daysOfTheWeek.allSatisfy({ $0.weekNumber == 0 }) else {
        throw recurrenceError("weekly day week_number must be zero")
      }

    case .monthly:
      guard rule.monthsOfTheYear.isEmpty, rule.weeksOfTheYear.isEmpty,
        rule.daysOfTheYear.isEmpty
      else {
        throw recurrenceError(
          "monthly recurrence does not accept months_of_the_year, weeks_of_the_year, or days_of_the_year"
        )
      }
      guard
        rule.daysOfTheWeek.allSatisfy({
          $0.weekNumber != Int.min && abs($0.weekNumber) <= 5
        })
      else {
        throw recurrenceError("monthly day week_number must be between -5 and 5")
      }

    case .yearly:
      guard rule.daysOfTheMonth.isEmpty else {
        throw recurrenceError("yearly recurrence does not accept days_of_the_month")
      }
      guard
        rule.daysOfTheWeek.allSatisfy({
          $0.weekNumber != Int.min && abs($0.weekNumber) <= 53
        })
      else {
        throw recurrenceError("yearly day week_number must be between -53 and 53")
      }
    }

    if !rule.setPositions.isEmpty {
      let hasSelector =
        !rule.daysOfTheWeek.isEmpty || !rule.daysOfTheMonth.isEmpty
        || !rule.monthsOfTheYear.isEmpty || !rule.weeksOfTheYear.isEmpty
        || !rule.daysOfTheYear.isEmpty
      guard hasSelector else {
        throw recurrenceError("set_positions requires at least one recurrence selector")
      }
    }
  }

  private static func validateNumbers(
    _ values: [Int],
    absoluteRange: ClosedRange<Int>,
    field: String
  ) throws {
    guard Set(values).count == values.count else {
      throw recurrenceError("\(field) must not contain duplicates")
    }
    guard
      values.allSatisfy({
        $0 != 0 && $0 != Int.min && absoluteRange.contains(abs($0))
      })
    else {
      throw recurrenceError(
        "\(field) values must be non-zero and between -\(absoluteRange.upperBound) and \(absoluteRange.upperBound)"
      )
    }
  }

  private static func validatePositiveNumbers(
    _ values: [Int],
    range: ClosedRange<Int>,
    field: String
  ) throws {
    guard Set(values).count == values.count else {
      throw recurrenceError("\(field) must not contain duplicates")
    }
    guard values.allSatisfy(range.contains) else {
      throw recurrenceError(
        "\(field) values must be between \(range.lowerBound) and \(range.upperBound)"
      )
    }
  }

  private static func validateUnique<Value: Hashable>(_ values: [Value], field: String) throws {
    guard Set(values).count == values.count else {
      throw recurrenceError("\(field) must not contain duplicates")
    }
  }

  private static func recurrenceError(_ reason: String) -> CalendarEventRuntimeError {
    .invalidInput(argument: "recurrence", reason: reason)
  }
}
