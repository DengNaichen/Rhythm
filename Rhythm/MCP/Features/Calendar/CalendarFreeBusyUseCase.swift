import Foundation

struct CalendarFreeBusyUseCase {
  private static let maximumRangeDays = 31
  private static let maximumCandidateEvents = 250

  let runtime: EventKitRuntime
  let now: () -> Date
  let calendar: Calendar

  init(
    runtime: EventKitRuntime,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = .eventKitGregorian
  ) {
    self.runtime = runtime
    self.now = now
    self.calendar = calendar
  }

  func execute(arguments: [String: Value]) throws -> CalendarFreeBusyResult {
    try requireCalendarAuthorization(runtime)
    let decoder = ToolArgumentsDecoder(arguments: arguments)
    let range = try DateRangeNormalizer.normalizeCalendarRange(
      from: try decoder.requiredString("from"),
      to: try decoder.requiredString("to"),
      now: now,
      calendar: calendar
    )
    guard
      let maximumEnd = calendar.date(
        byAdding: .day,
        value: Self.maximumRangeDays,
        to: range.from
      ),
      range.to <= maximumEnd
    else {
      throw ServiceToolError.invalidValue(
        argument: "to",
        reason: "free/busy ranges cannot exceed \(Self.maximumRangeDays) days"
      )
    }
    let includeAllDay = try decoder.optionalBool("include_all_day") ?? true
    let includeTentative = try decoder.optionalBool("include_tentative") ?? true

    let fetched = try runtime.fetchEvents(
      CalendarEventsFetchInput(
        range: range,
        calendars: try decoder.calendarReferences(),
        includeAllDay: includeAllDay
      )
    )
    let candidates = busyCandidates(
      fetched,
      range: range,
      includeAllDay: includeAllDay,
      includeTentative: includeTentative
    )
    guard candidates.count <= Self.maximumCandidateEvents else {
      throw ServiceToolError.invalidValue(
        argument: "to",
        reason:
          "free/busy matched \(candidates.count) busy events; narrow the range or calendars below \(Self.maximumCandidateEvents)"
      )
    }
    let busy = mergedBusyWindows(candidates)
    return CalendarFreeBusyResult(
      from: EventKitDateFormatting.iso8601String(from: range.from),
      to: EventKitDateFormatting.iso8601String(from: range.to),
      busy: busy,
      free: freeWindows(in: range, around: busy),
      conflicts: conflictWindows(candidates)
    )
  }

  private func busyCandidates(
    _ records: [CalendarEventRecord],
    range: DateRange,
    includeAllDay: Bool,
    includeTentative: Bool
  ) -> [BusyCandidate] {
    records.compactMap { record in
      guard record.status != CalendarEventStatusFilter.canceled.rawValue,
        record.availability != CalendarAvailabilityFilter.free.rawValue,
        includeAllDay || !record.isAllDay,
        includeTentative
          || (record.status != CalendarEventStatusFilter.tentative.rawValue
            && record.availability != CalendarAvailabilityFilter.tentative.rawValue)
      else {
        return nil
      }

      let start = max(record.startAt, range.from)
      let end = min(record.endAt, range.to)
      guard end > start else { return nil }
      return BusyCandidate(start: start, end: end, event: CalendarBusyEventDTO(record))
    }
    .sorted {
      if $0.start == $1.start { return $0.end < $1.end }
      return $0.start < $1.start
    }
  }

  private func mergedBusyWindows(_ candidates: [BusyCandidate]) -> [CalendarBusyWindowDTO] {
    guard let first = candidates.first else { return [] }
    var start = first.start
    var end = first.end
    var events = [first.event]
    var result: [CalendarBusyWindowDTO] = []

    for candidate in candidates.dropFirst() {
      if candidate.start <= end {
        end = max(end, candidate.end)
        events.append(candidate.event)
      } else {
        result.append(CalendarBusyWindowDTO(start: start, end: end, events: unique(events)))
        start = candidate.start
        end = candidate.end
        events = [candidate.event]
      }
    }
    result.append(CalendarBusyWindowDTO(start: start, end: end, events: unique(events)))
    return result
  }

  private func freeWindows(
    in range: DateRange,
    around busy: [CalendarBusyWindowDTO]
  ) -> [CalendarTimeWindowDTO] {
    var cursor = range.from
    var result: [CalendarTimeWindowDTO] = []
    for window in busy {
      if window.startDate > cursor {
        result.append(CalendarTimeWindowDTO(start: cursor, end: window.startDate))
      }
      cursor = max(cursor, window.endDate)
    }
    if cursor < range.to {
      result.append(CalendarTimeWindowDTO(start: cursor, end: range.to))
    }
    return result
  }

  private func conflictWindows(_ candidates: [BusyCandidate]) -> [CalendarConflictDTO] {
    let boundaries = Set(candidates.flatMap { [$0.start, $0.end] }).sorted()
    guard boundaries.count >= 2 else { return [] }
    let starts = Dictionary(grouping: candidates, by: \.start)
    let ends = Dictionary(grouping: candidates, by: \.end)
    var active: [String: (event: CalendarBusyEventDTO, count: Int)] = [:]
    var result: [CalendarConflictDTO] = []
    var previousBoundary: Date?

    for boundary in boundaries {
      if let previousBoundary, boundary > previousBoundary, active.count >= 2 {
        let events = unique(active.values.map(\.event))
        if let last = result.last,
          last.endDate == previousBoundary,
          last.events.map(\.referenceKey) == events.map(\.referenceKey)
        {
          result[result.count - 1] = CalendarConflictDTO(
            start: last.startDate,
            end: boundary,
            events: events
          )
        } else {
          result.append(
            CalendarConflictDTO(start: previousBoundary, end: boundary, events: events)
          )
        }
      }

      for candidate in ends[boundary] ?? [] {
        let key = candidate.event.referenceKey
        if let current = active[key], current.count > 1 {
          active[key] = (current.event, current.count - 1)
        } else {
          active.removeValue(forKey: key)
        }
      }
      for candidate in starts[boundary] ?? [] {
        let key = candidate.event.referenceKey
        if let current = active[key] {
          active[key] = (current.event, current.count + 1)
        } else {
          active[key] = (candidate.event, 1)
        }
      }
      previousBoundary = boundary
    }
    return result
  }

  private func unique(_ events: [CalendarBusyEventDTO]) -> [CalendarBusyEventDTO] {
    var seen = Set<String>()
    return
      events
      .sorted {
        if $0.startDate == $1.startDate { return $0.referenceKey < $1.referenceKey }
        return $0.startDate < $1.startDate
      }
      .filter { seen.insert($0.referenceKey).inserted }
  }
}

private struct BusyCandidate {
  let start: Date
  let end: Date
  let event: CalendarBusyEventDTO
}

nonisolated struct CalendarFreeBusyResult: Encodable, Equatable {
  let from: String
  let to: String
  let busy: [CalendarBusyWindowDTO]
  let free: [CalendarTimeWindowDTO]
  let conflicts: [CalendarConflictDTO]

  enum CodingKeys: String, CodingKey {
    case from
    case to
    case busy
    case free
    case conflicts
  }
}

nonisolated struct CalendarTimeWindowDTO: Encodable, Equatable {
  let startAt: String
  let endAt: String
  let startDate: Date
  let endDate: Date

  enum CodingKeys: String, CodingKey {
    case startAt = "start_at"
    case endAt = "end_at"
  }

  init(start: Date, end: Date) {
    startAt = EventKitDateFormatting.iso8601String(from: start)
    endAt = EventKitDateFormatting.iso8601String(from: end)
    startDate = start
    endDate = end
  }
}

nonisolated struct CalendarBusyWindowDTO: Encodable, Equatable {
  let startAt: String
  let endAt: String
  let eventCount: Int
  let events: [CalendarBusyEventDTO]
  let startDate: Date
  let endDate: Date

  enum CodingKeys: String, CodingKey {
    case startAt = "start_at"
    case endAt = "end_at"
    case eventCount = "event_count"
    case events
  }

  init(start: Date, end: Date, events: [CalendarBusyEventDTO]) {
    startAt = EventKitDateFormatting.iso8601String(from: start)
    endAt = EventKitDateFormatting.iso8601String(from: end)
    eventCount = events.count
    self.events = events
    startDate = start
    endDate = end
  }
}

nonisolated struct CalendarConflictDTO: Encodable, Equatable {
  let startAt: String
  let endAt: String
  let eventCount: Int
  let events: [CalendarBusyEventDTO]
  let startDate: Date
  let endDate: Date

  enum CodingKeys: String, CodingKey {
    case startAt = "start_at"
    case endAt = "end_at"
    case eventCount = "event_count"
    case events
  }

  init(start: Date, end: Date, events: [CalendarBusyEventDTO]) {
    startAt = EventKitDateFormatting.iso8601String(from: start)
    endAt = EventKitDateFormatting.iso8601String(from: end)
    eventCount = events.count
    self.events = events
    startDate = start
    endDate = end
  }
}

nonisolated struct CalendarBusyEventDTO: Encodable, Equatable {
  let id: String
  let occurrenceStart: String?
  let originalStartAt: String?
  let title: String
  let startAt: String
  let endAt: String
  let allDayStartDate: String?
  let allDayEndDate: String?
  let isAllDay: Bool
  let availability: String
  let calendarID: String
  let calendarTitle: String
  let startDate: Date
  let referenceKey: String

  enum CodingKeys: String, CodingKey {
    case id
    case occurrenceStart = "occurrence_start"
    case originalStartAt = "original_start_at"
    case title
    case startAt = "start_at"
    case endAt = "end_at"
    case allDayStartDate = "start_date"
    case allDayEndDate = "end_date"
    case isAllDay = "is_all_day"
    case availability
    case calendarID = "calendar_id"
    case calendarTitle = "calendar_title"
  }

  init(_ record: CalendarEventRecord) {
    let occurrenceDate = record.occurrenceStart
    let originalDate = record.originalStartAt
    id = record.id
    occurrenceStart = occurrenceDate.map(EventKitDateFormatting.iso8601String(from:))
    originalStartAt = originalDate.map(EventKitDateFormatting.iso8601String(from:))
    title = record.title
    startAt = EventKitDateFormatting.iso8601String(from: record.startAt)
    endAt = EventKitDateFormatting.iso8601String(from: record.endAt)
    allDayStartDate =
      record.isAllDay
      ? EventKitDateFormatting.localDateString(from: record.startAt) : nil
    allDayEndDate =
      record.isAllDay
      ? EventKitDateFormatting.localDateString(from: record.endAt) : nil
    isAllDay = record.isAllDay
    availability = record.availability
    calendarID = record.calendarID
    calendarTitle = record.calendarTitle
    startDate = record.startAt
    referenceKey =
      "\(record.id)\u{1f}\(occurrenceDate?.timeIntervalSinceReferenceDate ?? -1)\u{1f}\(originalDate?.timeIntervalSinceReferenceDate ?? -1)"
  }
}
