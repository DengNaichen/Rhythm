import EventKit
import Foundation

private let remindersServiceName = "Reminders"

struct RemindersListsUseCase {
    let runtime: EventKitRuntime

    func execute() throws -> [EventKitListDTO] {
        try requireAuthorization()
        return runtime.listReminderLists().map(EventKitListDTO.init)
    }

    private func requireAuthorization() throws {
        guard runtime.reminderAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: remindersServiceName)
        }
    }
}

struct RemindersItemsFetchUseCase {
    let runtime: EventKitRuntime
    let calendar: Calendar

    init(
        runtime: EventKitRuntime,
        calendar: Calendar = .current
    ) {
        self.runtime = runtime
        self.calendar = calendar
    }

    func execute(arguments: [String: Value]) async throws -> [ReminderItemDTO] {
        try await runtime.requestReminderAccess()
        try requireAuthorization()

        let decoder = ToolArgumentsDecoder(arguments: arguments)
        let range = try DateRangeNormalizer.normalizeOptionalRange(
            from: try decoder.optionalString("from"),
            to: try decoder.optionalString("to"),
            calendar: calendar
        )
        let completion = try decoder.enumValue(
            for: "completion",
            default: ReminderCompletionFilter.all
        )
        let listNames = try decoder.optionalStringArray("list_names")
        let query = try decoder.optionalString("query")

        let input = ReminderItemsFetchInput(
            completion: completion,
            range: range,
            listNames: listNames.map { Set($0.map { $0.lowercased() }) },
            query: query
        )

        var records = try await runtime.fetchReminders(input)

        if let query = input.query?.lowercased(), !query.isEmpty {
            records = records.filter { $0.title.lowercased().contains(query) }
        }

        return records
            .sorted { lhs, rhs in
                let lhsDate = lhs.dueAt ?? lhs.completedAt ?? Date.distantFuture
                let rhsDate = rhs.dueAt ?? rhs.completedAt ?? Date.distantFuture
                return lhsDate < rhsDate
            }
            .map(ReminderItemDTO.init)
    }

    private func requireAuthorization() throws {
        guard runtime.reminderAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: remindersServiceName)
        }
    }
}

struct RemindersItemCreateUseCase {
    let runtime: EventKitRuntime
    let calendar: Calendar

    init(
        runtime: EventKitRuntime,
        calendar: Calendar = .current
    ) {
        self.runtime = runtime
        self.calendar = calendar
    }

    func execute(arguments: [String: Value]) async throws -> ReminderItemDTO {
        try await runtime.requestReminderAccess()
        try requireAuthorization()

        let decoder = ToolArgumentsDecoder(arguments: arguments)
        let title = try decoder.requiredString("title")
        let dueAt: Date?
        if let dueAtRaw = try decoder.optionalString("due_at") {
            dueAt = try DateRangeNormalizer.normalizeSingleDate(
                dueAtRaw,
                argument: "due_at",
                calendar: calendar
            )
        } else {
            dueAt = nil
        }

        let alarmOffsets = try decodeAlarms(from: decoder)

        let input = ReminderItemCreateInput(
            title: title,
            dueAt: dueAt,
            listName: try decoder.optionalString("list_name"),
            notes: try decoder.optionalString("notes"),
            priority: try decoder.enumValue(for: "priority", default: ReminderPriorityFilter.none),
            alarms: alarmOffsets
        )

        return ReminderItemDTO(try runtime.createReminder(input))
    }

    private func decodeAlarms(from decoder: ToolArgumentsDecoder) throws -> [Int] {
        guard let alarmValues = try decoder.optionalArray("alarms") else {
            return []
        }

        var result: [Int] = []
        result.reserveCapacity(alarmValues.count)

        for (index, alarmValue) in alarmValues.enumerated() {
            guard let intValue = alarmValue.intValue else {
                throw ServiceToolError.invalidType(
                    argument: "alarms[\(index)]",
                    expected: "integer"
                )
            }
            guard intValue >= 0 else {
                throw ServiceToolError.invalidValue(
                    argument: "alarms[\(index)]",
                    reason: "minutes must be greater than or equal to 0"
                )
            }
            result.append(intValue)
        }

        return result
    }

    private func requireAuthorization() throws {
        guard runtime.reminderAuthorizationStatus() == .fullAccess else {
            throw ServiceToolError.unauthorized(service: remindersServiceName)
        }
    }
}
