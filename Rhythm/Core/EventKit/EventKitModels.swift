import Foundation

nonisolated enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case granted
    case denied
}

nonisolated enum CalendarEventStatusFilter: String, CaseIterable, Sendable {
    case none
    case tentative
    case confirmed
    case canceled
}

nonisolated enum CalendarAvailabilityFilter: String, CaseIterable, Sendable {
    case busy
    case free
    case tentative
    case unavailable
}

nonisolated enum ReminderCompletionFilter: String, CaseIterable, Sendable {
    case all
    case completed
    case incomplete
}

nonisolated enum ReminderPriorityFilter: String, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
}

nonisolated enum CalendarAlarmKind: String, CaseIterable, Sendable {
    case relative
    case absolute
    case proximity
}

nonisolated enum AlarmProximityKind: String, CaseIterable, Sendable {
    case enter
    case leave
}

nonisolated enum EventKitDateFormatting {
    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

nonisolated struct EventKitListRecord: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let source: String
    let color: String
    let isEditable: Bool
    let isSubscribed: Bool
}

nonisolated struct CalendarEventRecord: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let startAt: Date
    let endAt: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let status: String
    let availability: String
    let hasAlarms: Bool
    let isRecurring: Bool
    let listTitle: String
}

nonisolated struct ReminderItemRecord: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueAt: Date?
    let completedAt: Date?
    let priority: String
    let notes: String?
    let hasAlarms: Bool
    let listTitle: String
}

nonisolated struct CalendarEventsFetchInput: Equatable, Sendable {
    let range: DateRange
    let listNames: Set<String>?
    let query: String?
    let includeAllDay: Bool
    let status: CalendarEventStatusFilter?
    let availability: CalendarAvailabilityFilter?
    let hasAlarms: Bool?
    let isRecurring: Bool?
}

nonisolated enum CalendarAlarmInput: Equatable, Sendable {
    case relative(minutes: Int, emailAddress: String?)
    case absolute(at: Date, emailAddress: String?)
    case proximity(
        proximity: AlarmProximityKind,
        locationTitle: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        emailAddress: String?
    )
}

nonisolated struct CalendarEventCreateInput: Equatable, Sendable {
    let title: String
    let startAt: Date
    let endAt: Date
    let listName: String?
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let availability: CalendarAvailabilityFilter?
    let alarms: [CalendarAlarmInput]
}

nonisolated struct ReminderItemsFetchInput: Equatable, Sendable {
    let completion: ReminderCompletionFilter
    let range: OptionalDateRange
    let listNames: Set<String>?
    let query: String?
}

nonisolated struct ReminderItemCreateInput: Equatable, Sendable {
    let title: String
    let dueAt: Date?
    let listName: String?
    let notes: String?
    let priority: ReminderPriorityFilter
    let alarms: [Int]
}

nonisolated struct EventKitListDTO: Encodable, Equatable {
    let id: String
    let title: String
    let source: String
    let color: String
    let isEditable: Bool
    let isSubscribed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case color
        case isEditable = "is_editable"
        case isSubscribed = "is_subscribed"
    }

    init(_ record: EventKitListRecord) {
        id = record.id
        title = record.title
        source = record.source
        color = record.color
        isEditable = record.isEditable
        isSubscribed = record.isSubscribed
    }
}

nonisolated struct CalendarEventDTO: Encodable, Equatable {
    let id: String
    let title: String
    let startAt: String
    let endAt: String
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let url: String?
    let status: String
    let availability: String
    let hasAlarms: Bool
    let isRecurring: Bool
    let listTitle: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case location
        case notes
        case url
        case status
        case availability
        case hasAlarms = "has_alarms"
        case isRecurring = "is_recurring"
        case listTitle = "list_title"
    }

    init(_ record: CalendarEventRecord) {
        id = record.id
        title = record.title
        startAt = EventKitDateFormatting.iso8601String(from: record.startAt)
        endAt = EventKitDateFormatting.iso8601String(from: record.endAt)
        isAllDay = record.isAllDay
        location = record.location
        notes = record.notes
        url = record.url
        status = record.status
        availability = record.availability
        hasAlarms = record.hasAlarms
        isRecurring = record.isRecurring
        listTitle = record.listTitle
    }
}

nonisolated struct ReminderItemDTO: Encodable, Equatable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueAt: String?
    let completedAt: String?
    let priority: String
    let notes: String?
    let hasAlarms: Bool
    let listTitle: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted = "is_completed"
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case priority
        case notes
        case hasAlarms = "has_alarms"
        case listTitle = "list_title"
    }

    init(_ record: ReminderItemRecord) {
        id = record.id
        title = record.title
        isCompleted = record.isCompleted
        dueAt = record.dueAt.map(EventKitDateFormatting.iso8601String(from:))
        completedAt = record.completedAt.map(EventKitDateFormatting.iso8601String(from:))
        priority = record.priority
        notes = record.notes
        hasAlarms = record.hasAlarms
        listTitle = record.listTitle
    }
}
