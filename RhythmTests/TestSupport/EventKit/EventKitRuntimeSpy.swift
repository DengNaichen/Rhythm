import EventKit
import Foundation

@testable import Rhythm

struct CalendarResolutionCall: Equatable {
  let reference: EventKitCalendarReference
  let requireWritable: Bool
}

struct CalendarUpdateCall: Equatable {
  let reference: CalendarEventReference
  let input: CalendarEventUpdateInput
  let span: CalendarEventSpan
}

struct CalendarDeleteCall: Equatable {
  let reference: CalendarEventReference
  let span: CalendarEventSpan
}

@MainActor
final class EventKitRuntimeSpy: EventKitRuntime {
  var authorizationStatus: EKAuthorizationStatus = .fullAccess
  var requestAccessError: Error?
  var resolveCalendarError: Error?
  var fetchError: Error?
  var eventError: Error?
  var createError: Error?
  var updateError: Error?
  var deleteError: Error?

  var calendars = [CalendarTestFixtures.writableCalendar]
  var events = [CalendarTestFixtures.event]
  var createResult = CalendarTestFixtures.event
  var updateResult = CalendarTestFixtures.event
  var deleteResult = CalendarTestFixtures.event

  private(set) var requestAccessCallCount = 0
  private(set) var resolutionCalls: [CalendarResolutionCall] = []
  private(set) var fetchInputs: [CalendarEventsFetchInput] = []
  private(set) var eventReferences: [CalendarEventReference] = []
  private(set) var createInputs: [CalendarEventCreateInput] = []
  private(set) var updateCalls: [CalendarUpdateCall] = []
  private(set) var deleteCalls: [CalendarDeleteCall] = []

  func eventAuthorizationStatus() -> EKAuthorizationStatus {
    authorizationStatus
  }

  func requestEventAccess() async throws {
    requestAccessCallCount += 1
    if let requestAccessError { throw requestAccessError }
  }

  func listEventCalendars() -> [EventKitListRecord] {
    calendars
  }

  func resolveEventCalendar(
    _ reference: EventKitCalendarReference,
    requireWritable: Bool
  ) throws -> EventKitListRecord {
    resolutionCalls.append(
      CalendarResolutionCall(reference: reference, requireWritable: requireWritable)
    )
    if let resolveCalendarError { throw resolveCalendarError }

    let value = reference.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw CalendarEventRuntimeError.emptyCalendarReference(kind: reference.kind)
    }

    let matches: [EventKitListRecord]
    switch reference {
    case .id:
      matches = calendars.filter { $0.id == value }
    case .title:
      matches = calendars.filter {
        $0.title.caseInsensitiveCompare(value) == .orderedSame
      }
    }

    guard let calendar = matches.first else {
      throw CalendarEventRuntimeError.calendarNotFound(reference)
    }
    if case .title = reference, matches.count > 1 {
      throw CalendarEventRuntimeError.ambiguousCalendarTitle(
        title: value,
        matchingIDs: matches.map(\.id).sorted()
      )
    }
    if requireWritable, !calendar.isEditable {
      throw CalendarEventRuntimeError.calendarNotWritable(
        id: calendar.id,
        title: calendar.title
      )
    }
    return calendar
  }

  func fetchEvents(_ input: CalendarEventsFetchInput) throws -> [CalendarEventRecord] {
    fetchInputs.append(input)
    if let fetchError { throw fetchError }
    if let references = input.calendars {
      for reference in references {
        _ = try resolveEventCalendar(reference, requireWritable: false)
      }
    }
    return events
  }

  func event(_ reference: CalendarEventReference) throws -> CalendarEventRecord {
    eventReferences.append(reference)
    if let eventError { throw eventError }

    guard
      let event = events.first(where: { candidate in
        guard candidate.id == reference.id else { return false }
        if let occurrenceStart = reference.occurrenceStart {
          let matchesActualStart = candidate.occurrenceStart == occurrenceStart
          let matchesLegacyOriginalStart =
            reference.originalStartAt == nil
            && candidate.originalStartAt == occurrenceStart
          guard matchesActualStart || matchesLegacyOriginalStart else {
            return false
          }
        }
        if let originalStartAt = reference.originalStartAt,
          candidate.originalStartAt != originalStartAt
        {
          return false
        }
        return true
      })
    else {
      throw CalendarEventRuntimeError.eventNotFound(reference)
    }
    return event
  }

  func createEvent(_ input: CalendarEventCreateInput) throws -> CalendarEventRecord {
    createInputs.append(input)
    if let createError { throw createError }
    if let reference = input.calendar {
      _ = try resolveEventCalendar(reference, requireWritable: true)
    }
    return createResult
  }

  func updateEvent(
    _ reference: CalendarEventReference,
    input: CalendarEventUpdateInput,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord {
    updateCalls.append(CalendarUpdateCall(reference: reference, input: input, span: span))
    if let updateError { throw updateError }
    if let calendarReference = input.calendar {
      _ = try resolveEventCalendar(calendarReference, requireWritable: true)
    }
    return updateResult
  }

  func deleteEvent(
    _ reference: CalendarEventReference,
    span: CalendarEventSpan
  ) throws -> CalendarEventRecord {
    deleteCalls.append(CalendarDeleteCall(reference: reference, span: span))
    if let deleteError { throw deleteError }
    return deleteResult
  }
}
