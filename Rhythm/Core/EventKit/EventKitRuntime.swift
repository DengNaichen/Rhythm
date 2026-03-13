import AppKit
import CoreLocation
import EventKit
import Foundation

@MainActor
protocol EventKitRuntime: AnyObject {
    func eventAuthorizationStatus() -> EKAuthorizationStatus
    func reminderAuthorizationStatus() -> EKAuthorizationStatus
    func requestEventAccess() async throws
    func requestReminderAccess() async throws

    func listEventCalendars() -> [EventKitListRecord]
    func fetchEvents(from: Date, to: Date, listNames: Set<String>?) -> [CalendarEventRecord]
    func createEvent(_ input: CalendarEventCreateInput) throws -> CalendarEventRecord

    func listReminderLists() -> [EventKitListRecord]
    func fetchReminders(_ input: ReminderItemsFetchInput) async throws -> [ReminderItemRecord]
    func createReminder(_ input: ReminderItemCreateInput) throws -> ReminderItemRecord
}

@MainActor
final class LiveEventKitRuntime: EventKitRuntime {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = .current
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func eventAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestEventAccess() async throws {
        try await eventStore.requestFullAccessToEvents()
    }

    func requestReminderAccess() async throws {
        try await eventStore.requestFullAccessToReminders()
    }

    func listEventCalendars() -> [EventKitListRecord] {
        eventStore.calendars(for: .event).map(Self.makeListRecord(from:))
    }

    func fetchEvents(from: Date, to: Date, listNames: Set<String>?) -> [CalendarEventRecord] {
        var calendars = eventStore.calendars(for: .event)
        if let listNames, !listNames.isEmpty {
            let requested = Set(listNames.map { $0.lowercased() })
            calendars = calendars.filter { requested.contains($0.title.lowercased()) }
        }

        let predicate = eventStore.predicateForEvents(
            withStart: from,
            end: to,
            calendars: calendars
        )

        return eventStore.events(matching: predicate).map(Self.makeEventRecord(from:))
    }

    func createEvent(_ input: CalendarEventCreateInput) throws -> CalendarEventRecord {
        let event = EKEvent(eventStore: eventStore)
        event.title = input.title

        if input.isAllDay {
            var startComponents = calendar.dateComponents([.year, .month, .day], from: input.startAt)
            startComponents.hour = 0
            startComponents.minute = 0
            startComponents.second = 0

            var endComponents = calendar.dateComponents([.year, .month, .day], from: input.endAt)
            endComponents.hour = 23
            endComponents.minute = 59
            endComponents.second = 59

            event.startDate = calendar.date(from: startComponents)
            event.endDate = calendar.date(from: endComponents)
            event.isAllDay = true
        } else {
            event.startDate = input.startAt
            event.endDate = input.endAt
            event.isAllDay = false
        }

        if let listName = input.listName,
            let selectedCalendar = eventStore.calendars(for: .event).first(where: {
                $0.title.caseInsensitiveCompare(listName) == .orderedSame
            })
        {
            event.calendar = selectedCalendar
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }

        event.location = input.location
        event.notes = input.notes
        event.url = input.url

        if let availability = input.availability {
            event.availability = EKEventAvailability(availability.rawValue)
        }

        event.alarms = try input.alarms.map(makeEventAlarm(from:))

        try eventStore.save(event, span: .thisEvent)
        return Self.makeEventRecord(from: event)
    }

    func listReminderLists() -> [EventKitListRecord] {
        eventStore.calendars(for: .reminder).map(Self.makeListRecord(from:))
    }

    func fetchReminders(_ input: ReminderItemsFetchInput) async throws -> [ReminderItemRecord] {
        var reminderLists = eventStore.calendars(for: .reminder)
        if let listNames = input.listNames, !listNames.isEmpty {
            let requested = Set(listNames.map { $0.lowercased() })
            reminderLists = reminderLists.filter { requested.contains($0.title.lowercased()) }
        }

        let predicate: NSPredicate
        switch input.completion {
        case .completed:
            predicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: input.range.from,
                ending: input.range.to,
                calendars: reminderLists
            )
        case .incomplete:
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: input.range.from,
                ending: input.range.to,
                calendars: reminderLists
            )
        case .all:
            predicate = eventStore.predicateForReminders(in: reminderLists)
        }

        let reminders = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[EKReminder], Error>) in
            eventStore.fetchReminders(matching: predicate) { fetchedReminders in
                continuation.resume(returning: fetchedReminders ?? [])
            }
        }

        var records = reminders.map(Self.makeReminderRecord(from:))

        if input.completion == .all, input.range.from != nil || input.range.to != nil {
            records = records.filter { record in
                guard let referenceDate = record.dueAt ?? record.completedAt else {
                    return false
                }

                if let fromDate = input.range.from, referenceDate < fromDate {
                    return false
                }
                if let toDate = input.range.to, referenceDate > toDate {
                    return false
                }
                return true
            }
        }

        return records
    }

    func createReminder(_ input: ReminderItemCreateInput) throws -> ReminderItemRecord {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = input.title

        if let listName = input.listName,
            let selectedCalendar = eventStore.calendars(for: .reminder).first(where: {
                $0.title.caseInsensitiveCompare(listName) == .orderedSame
            })
        {
            reminder.calendar = selectedCalendar
        } else {
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
        }

        if let dueAt = input.dueAt {
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueAt
            )
        }

        reminder.notes = input.notes
        reminder.priority = Int(EKReminderPriority.from(string: input.priority.rawValue).rawValue)
        reminder.alarms = input.alarms.map { EKAlarm(relativeOffset: TimeInterval(-$0 * 60)) }

        try eventStore.save(reminder, commit: true)
        return Self.makeReminderRecord(from: reminder)
    }

    private func makeEventAlarm(from input: CalendarAlarmInput) throws -> EKAlarm {
        switch input {
        case let .relative(minutes, emailAddress):
            let alarm = EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
            applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
            return alarm
        case let .absolute(date, emailAddress):
            let alarm = EKAlarm(absoluteDate: date)
            applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
            return alarm
        case let .proximity(proximity, locationTitle, latitude, longitude, radius, emailAddress):
            let alarm = EKAlarm()
            alarm.proximity = proximity == .enter ? .enter : .leave
            let structuredLocation = EKStructuredLocation(title: locationTitle)
            structuredLocation.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
            structuredLocation.radius = radius
            alarm.structuredLocation = structuredLocation
            applyAlarmMetadata(emailAddress: emailAddress, to: alarm)
            return alarm
        }
    }

    private func applyAlarmMetadata(emailAddress: String?, to alarm: EKAlarm) {
        if let emailAddress, !emailAddress.isEmpty {
            alarm.emailAddress = emailAddress
        }
    }

    nonisolated private static func makeListRecord(from calendar: EKCalendar) -> EventKitListRecord {
        EventKitListRecord(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            source: calendar.source.title,
            color: calendar.color.accessibilityName,
            isEditable: calendar.allowsContentModifications,
            isSubscribed: calendar.isSubscribed
        )
    }

    nonisolated private static func makeEventRecord(from event: EKEvent) -> CalendarEventRecord {
        CalendarEventRecord(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            startAt: event.startDate,
            endAt: event.endDate ?? event.startDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            status: event.status.mcpStatusValue,
            availability: event.availability.stringValue,
            hasAlarms: event.hasAlarms,
            isRecurring: event.hasRecurrenceRules,
            listTitle: event.calendar.title
        )
    }

    nonisolated private static func makeReminderRecord(from reminder: EKReminder) -> ReminderItemRecord {
        ReminderItemRecord(
            id: reminder.calendarItemIdentifier,
            title: reminder.title,
            isCompleted: reminder.isCompleted,
            dueAt: reminder.dueDateComponents?.date,
            completedAt: reminder.completionDate,
            priority: reminder.priority.mcpPriorityValue,
            notes: reminder.notes,
            hasAlarms: reminder.hasAlarms,
            listTitle: reminder.calendar.title
        )
    }
}
