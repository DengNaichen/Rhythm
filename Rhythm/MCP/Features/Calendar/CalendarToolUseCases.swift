import EventKit
import Foundation

private let calendarServiceName = "Calendar"

struct CalendarListUseCase {
    let runtime: EventKitRuntime

    func execute() throws -> [EventKitListDTO] {
        try requireAuthorization()
        return runtime.listEventCalendars().map(EventKitListDTO.init)
    }

    private func requireAuthorization() throws {
        guard runtime.eventAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: calendarServiceName)
        }
    }
}

struct CalendarEventsFetchUseCase {
    let runtime: EventKitRuntime
    let now: () -> Date
    let calendar: Calendar

    init(
        runtime: EventKitRuntime,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.runtime = runtime
        self.now = now
        self.calendar = calendar
    }

    func execute(arguments: [String: Value]) throws -> [CalendarEventDTO] {
        try requireAuthorization()

        let decoder = ToolArgumentsDecoder(arguments: arguments)
        let range = try DateRangeNormalizer.normalizeCalendarRange(
            from: try decoder.optionalString("from"),
            to: try decoder.optionalString("to"),
            now: now,
            calendar: calendar
        )

        let listNames = try decoder.optionalStringArray("list_names")
        let query = try decoder.optionalString("query")
        let includeAllDay = try decoder.optionalBool("include_all_day") ?? true
        let status = try decoder.optionalEnumValue(for: "status", as: CalendarEventStatusFilter.self)
        let availability = try decoder.optionalEnumValue(
            for: "availability",
            as: CalendarAvailabilityFilter.self
        )
        let hasAlarms = try decoder.optionalBool("has_alarms")
        let isRecurring = try decoder.optionalBool("is_recurring")

        let input = CalendarEventsFetchInput(
            range: range,
            listNames: listNames.map { Set($0.map { $0.lowercased() }) },
            query: query,
            includeAllDay: includeAllDay,
            status: status,
            availability: availability,
            hasAlarms: hasAlarms,
            isRecurring: isRecurring
        )

        var records = runtime.fetchEvents(
            from: input.range.from,
            to: input.range.to,
            listNames: input.listNames
        )

        if !input.includeAllDay {
            records = records.filter { !$0.isAllDay }
        }

        if let query = input.query?.lowercased(), !query.isEmpty {
            records = records.filter { record in
                record.title.lowercased().contains(query)
                    || (record.location?.lowercased().contains(query) ?? false)
            }
        }

        if let status = input.status {
            records = records.filter { $0.status == status.rawValue }
        }

        if let availability = input.availability {
            records = records.filter { $0.availability == availability.rawValue }
        }

        if let hasAlarms = input.hasAlarms {
            records = records.filter { $0.hasAlarms == hasAlarms }
        }

        if let isRecurring = input.isRecurring {
            records = records.filter { $0.isRecurring == isRecurring }
        }

        return records
            .sorted { $0.startAt < $1.startAt }
            .map(CalendarEventDTO.init)
    }

    private func requireAuthorization() throws {
        guard runtime.eventAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: calendarServiceName)
        }
    }
}

struct CalendarEventCreateUseCase {
    let runtime: EventKitRuntime
    let calendar: Calendar

    init(
        runtime: EventKitRuntime,
        calendar: Calendar = .current
    ) {
        self.runtime = runtime
        self.calendar = calendar
    }

    func execute(arguments: [String: Value]) async throws -> CalendarEventDTO {
        try await runtime.requestEventAccess()
        try requireAuthorization()

        let decoder = ToolArgumentsDecoder(arguments: arguments)
        let title = try decoder.requiredString("title")
        let startAtRaw = try decoder.requiredString("start_at")
        let endAtRaw = try decoder.requiredString("end_at")
        let startAt = try DateRangeNormalizer.normalizeSingleDate(
            startAtRaw,
            argument: "start_at",
            calendar: calendar
        )
        let endAt = try DateRangeNormalizer.normalizeSingleDate(
            endAtRaw,
            argument: "end_at",
            calendar: calendar
        )

        guard endAt >= startAt else {
            throw ServiceToolError.invalidValue(
                argument: "end_at",
                reason: "'end_at' must be later than or equal to 'start_at'"
            )
        }

        let isAllDay = try decoder.optionalBool("is_all_day") ?? false
        let urlString = try decoder.optionalString("url")
        let url: URL?
        if let urlString {
            guard let parsedURL = URL(string: urlString) else {
                throw ServiceToolError.invalidURL(argument: "url", value: urlString)
            }
            url = parsedURL
        } else {
            url = nil
        }

        let input = CalendarEventCreateInput(
            title: title,
            startAt: startAt,
            endAt: endAt,
            listName: try decoder.optionalString("list_name"),
            location: try decoder.optionalString("location"),
            notes: try decoder.optionalString("notes"),
            url: url,
            isAllDay: isAllDay,
            availability: try decoder.optionalEnumValue(
                for: "availability",
                as: CalendarAvailabilityFilter.self
            ),
            alarms: []
        )

        return CalendarEventDTO(try runtime.createEvent(input))
    }

    private func requireAuthorization() throws {
        guard runtime.eventAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: calendarServiceName)
        }
    }
}
