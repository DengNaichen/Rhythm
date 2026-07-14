import EventKit
import Foundation

extension LiveEventKitRuntime {
  func resolveCalendar(
    _ reference: EventKitCalendarReference,
    requireWritable: Bool
  ) throws -> EKCalendar {
    let rawValue = reference.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawValue.isEmpty else {
      throw CalendarEventRuntimeError.emptyCalendarReference(kind: reference.kind)
    }

    let resolved: EKCalendar
    switch reference {
    case .id:
      guard
        let calendar = eventStore.calendars(for: .event).first(where: {
          $0.calendarIdentifier == rawValue
        })
      else {
        throw CalendarEventRuntimeError.calendarNotFound(reference)
      }
      resolved = calendar
    case .title:
      let matches = eventStore.calendars(for: .event).filter {
        $0.title.caseInsensitiveCompare(rawValue) == .orderedSame
      }
      guard !matches.isEmpty else {
        throw CalendarEventRuntimeError.calendarNotFound(reference)
      }
      guard matches.count == 1, let calendar = matches.first else {
        throw CalendarEventRuntimeError.ambiguousCalendarTitle(
          title: rawValue,
          matchingIDs: matches.map(\.calendarIdentifier).sorted()
        )
      }
      resolved = calendar
    }

    if requireWritable, !resolved.allowsContentModifications {
      throw CalendarEventRuntimeError.calendarNotWritable(
        id: resolved.calendarIdentifier,
        title: resolved.title
      )
    }
    return resolved
  }

  func resolveCalendars(
    _ references: [EventKitCalendarReference]?
  ) throws -> [EKCalendar]? {
    guard let references else {
      return nil
    }

    var seen = Set<String>()
    return try references.compactMap { reference in
      let calendar = try resolveCalendar(reference, requireWritable: false)
      guard seen.insert(calendar.calendarIdentifier).inserted else {
        return nil
      }
      return calendar
    }
  }

  func resolveWritableCalendar(
    _ reference: EventKitCalendarReference?
  ) throws -> EKCalendar {
    if let reference {
      return try resolveCalendar(reference, requireWritable: true)
    }

    guard let calendar = eventStore.defaultCalendarForNewEvents,
      calendar.allowsContentModifications
    else {
      throw CalendarEventRuntimeError.defaultCalendarUnavailable
    }
    return calendar
  }

  func resolveEvent(_ reference: CalendarEventReference) throws -> EKEvent {
    let identifier = reference.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty else {
      throw CalendarEventRuntimeError.invalidInput(
        argument: "id",
        reason: "event ID must not be empty"
      )
    }

    let hasOccurrenceSelector =
      reference.occurrenceStart != nil || reference.originalStartAt != nil
    if let directMatch = eventStore.event(withIdentifier: identifier) {
      guard hasOccurrenceSelector else {
        return directMatch
      }
      if Self.matchesOccurrence(directMatch, reference: reference) {
        return directMatch
      }
    } else if !hasOccurrenceSelector {
      throw CalendarEventRuntimeError.eventNotFound(reference)
    }

    if let searchAnchor = reference.occurrenceStart ?? reference.originalStartAt {
      let searchStart = searchAnchor.addingTimeInterval(-1)
      let searchEnd = searchAnchor.addingTimeInterval(24 * 60 * 60)
      let predicate = eventStore.predicateForEvents(
        withStart: searchStart,
        end: searchEnd,
        calendars: nil
      )
      if let occurrence = eventStore.events(matching: predicate).first(where: { event in
        Self.matchesIdentifier(event, identifier: identifier)
          && Self.matchesOccurrence(event, reference: reference)
      }) {
        return occurrence
      }
    }

    throw CalendarEventRuntimeError.eventNotFound(reference)
  }

  func requireWritable(_ event: EKEvent, reference: CalendarEventReference) throws {
    guard let calendar = event.calendar, calendar.allowsContentModifications else {
      throw CalendarEventRuntimeError.eventNotWritable(
        id: reference.id,
        calendarTitle: event.calendar?.title ?? "Unknown"
      )
    }
  }

  private static func matchesIdentifier(_ event: EKEvent, identifier: String) -> Bool {
    event.eventIdentifier == identifier || event.calendarItemIdentifier == identifier
  }

  private static func matchesOccurrence(
    _ event: EKEvent,
    reference: CalendarEventReference
  ) -> Bool {
    if let occurrenceStart = reference.occurrenceStart {
      let matchesActualStart =
        event.startDate.map {
          abs($0.timeIntervalSince(occurrenceStart)) < 1
        } ?? false
      let matchesLegacyOriginalStart =
        reference.originalStartAt == nil
        && (event.occurrenceDate.map {
          abs($0.timeIntervalSince(occurrenceStart)) < 1
        } ?? false)
      guard matchesActualStart || matchesLegacyOriginalStart else {
        return false
      }
    }
    if let originalStartAt = reference.originalStartAt {
      guard
        event.occurrenceDate.map({ abs($0.timeIntervalSince(originalStartAt)) < 1 }) == true
      else {
        return false
      }
    }
    return true
  }
}
