import EventKit
import Foundation
import JSONSchema
import OrderedCollections

@MainActor
final class CalendarToolService: Service {
    let id = "calendar"
    let displayName = "Calendar"

    private let runtime: EventKitRuntime
    private let calendar: Calendar
    private let now: () -> Date

    init(
        runtime: EventKitRuntime,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.runtime = runtime
        self.calendar = calendar
        self.now = now
    }

    convenience init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(
            runtime: LiveEventKitRuntime(),
            calendar: calendar,
            now: now
        )
    }

    func tools() -> [Tool] {
        [
            Tool(
                name: "calendar_calendars_list",
                title: "List Calendars",
                description: "List available calendars.",
                systemImage: "list.bullet.rectangle",
                inputSchema: .object(
                    properties: [:],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { _ in
                try CalendarListUseCase(runtime: self.runtime).execute()
            },
            Tool(
                name: "calendar_events_fetch",
                title: "Fetch Events",
                description: "Fetch calendar events with date range and filter options.",
                systemImage: "magnifyingglass",
                inputSchema: .object(
                    properties: [
                        "from": .string(
                            description:
                                "Start date/time. If timezone is omitted, local time is assumed. Date-only uses local midnight.",
                            format: .dateTime
                        ),
                        "to": .string(
                            description:
                                "End date/time. If timezone is omitted, local time is assumed. Date-only is inclusive for the full day.",
                            format: .dateTime
                        ),
                        "list_names": .array(
                            description: "Calendar names to include. Uses all calendars when omitted.",
                            items: .string()
                        ),
                        "query": .string(
                            description: "Case-insensitive search against title and location."
                        ),
                        "include_all_day": .boolean(default: true),
                        "status": .string(
                            description: "Filter by event status.",
                            enum: CalendarEventStatusFilter.allCases.map { .string($0.rawValue) }
                        ),
                        "availability": .string(
                            description: "Filter by availability.",
                            enum: CalendarAvailabilityFilter.allCases.map { .string($0.rawValue) }
                        ),
                        "has_alarms": .boolean(),
                        "is_recurring": .boolean(),
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try CalendarEventsFetchUseCase(
                    runtime: self.runtime,
                    now: self.now,
                    calendar: self.calendar
                )
                .execute(arguments: arguments)
            },
            Tool(
                name: "calendar_events_create",
                title: "Create Event",
                description: "Create a calendar event.",
                systemImage: "calendar.badge.plus",
                inputSchema: .object(
                    properties: [
                        "title": .string(),
                        "start_at": .string(
                            description:
                                "Event start date/time. If timezone is omitted, local time is assumed. Date-only uses local midnight.",
                            format: .dateTime
                        ),
                        "end_at": .string(
                            description:
                                "Event end date/time. If timezone is omitted, local time is assumed. Date-only uses local midnight.",
                            format: .dateTime
                        ),
                        "list_name": .string(
                            description: "Calendar name. Uses default calendar when omitted."
                        ),
                        "location": .string(),
                        "notes": .string(),
                        "url": .string(format: .uri),
                        "is_all_day": .boolean(default: false),
                        "availability": .string(
                            default: .string(CalendarAvailabilityFilter.busy.rawValue),
                            enum: CalendarAvailabilityFilter.allCases.map { .string($0.rawValue) }
                        ),
                        "alarms": .array(
                            description: "Alarm objects (relative, absolute, or proximity).",
                            items: .object(
                                properties: [
                                    "type": .string(
                                        enum: CalendarAlarmKind.allCases.map { .string($0.rawValue) }
                                    ),
                                    "minutes": .integer(
                                        description: "Minutes before the event for relative alarms."
                                    ),
                                    "at": .string(
                                        description: "Absolute alarm date-time.",
                                        format: .dateTime
                                    ),
                                    "proximity": .string(
                                        default: .string(AlarmProximityKind.enter.rawValue),
                                        enum: AlarmProximityKind.allCases.map { .string($0.rawValue) }
                                    ),
                                    "location_title": .string(),
                                    "latitude": .number(),
                                    "longitude": .number(),
                                    "radius": .number(default: .int(200)),
                                    "email_address": .string(),
                                ],
                                additionalProperties: false
                            )
                        ),
                    ],
                    required: ["title", "start_at", "end_at"],
                    additionalProperties: false
                ),
                destructiveHint: true,
                openWorldHint: false
            ) { arguments in
                try await CalendarEventCreateUseCase(
                    runtime: self.runtime,
                    calendar: self.calendar
                )
                .execute(arguments: arguments)
            },
        ]
    }

    func isActivated() async -> Bool {
        runtime.eventAuthorizationStatus() == .fullAccess
    }

    func activate() async throws {
        try await runtime.requestEventAccess()
    }

    func authorizationState() -> CalendarAuthorizationState {
        switch runtime.eventAuthorizationStatus() {
        case .fullAccess, .writeOnly:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async throws -> CalendarAuthorizationState {
        switch authorizationState() {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            try await runtime.requestEventAccess()
            return authorizationState()
        }
    }

    func fetchUpcomingEvents(referenceDate: Date, daysAhead: Int) -> [CalendarEventRecord] {
        guard authorizationState() == .granted else {
            return []
        }

        let startDate = calendar.startOfDay(for: referenceDate)
        let endDate = calendar.date(byAdding: .day, value: max(daysAhead, 1), to: startDate)
            ?? startDate

        return runtime.fetchEvents(from: startDate, to: endDate, listNames: nil)
            .sorted { $0.startAt < $1.startAt }
    }
}
