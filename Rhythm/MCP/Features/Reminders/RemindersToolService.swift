import EventKit
import Foundation
import JSONSchema
import OrderedCollections

@MainActor
final class RemindersToolService: Service {
    let id = "reminders"
    let displayName = "Reminders"

    private let runtime: EventKitRuntime
    private let calendar: Calendar

    init(
        runtime: EventKitRuntime,
        calendar: Calendar = .current
    ) {
        self.runtime = runtime
        self.calendar = calendar
    }

    convenience init(calendar: Calendar = .current) {
        self.init(
            runtime: LiveEventKitRuntime(),
            calendar: calendar
        )
    }

    func tools() -> [Tool] {
        [
            Tool(
                name: "reminders_lists_list",
                title: "List Reminder Lists",
                description: "List available reminder lists.",
                systemImage: "list.bullet.rectangle",
                inputSchema: .object(
                    properties: [:],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { _ in
                try RemindersListsUseCase(runtime: self.runtime).execute()
            },
            Tool(
                name: "reminders_items_fetch",
                title: "Fetch Reminder Items",
                description: "Fetch reminder items with completion and date filters.",
                systemImage: "magnifyingglass",
                inputSchema: .object(
                    properties: [
                        "completion": .string(
                            description: "Completion filter.",
                            default: .string(ReminderCompletionFilter.all.rawValue),
                            enum: ReminderCompletionFilter.allCases.map { .string($0.rawValue) }
                        ),
                        "from": .string(
                            description:
                                "Start date/time range. If timezone is omitted, local time is assumed. Date-only uses local midnight.",
                            format: .dateTime
                        ),
                        "to": .string(
                            description:
                                "End date/time range. If timezone is omitted, local time is assumed. Date-only is inclusive for the full day.",
                            format: .dateTime
                        ),
                        "list_names": .array(
                            description: "Reminder list names to include.",
                            items: .string()
                        ),
                        "query": .string(
                            description: "Case-insensitive search against reminder title."
                        ),
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await RemindersItemsFetchUseCase(
                    runtime: self.runtime,
                    calendar: self.calendar
                )
                .execute(arguments: arguments)
            },
            Tool(
                name: "reminders_items_create",
                title: "Create Reminder Item",
                description: "Create a reminder item.",
                systemImage: "checklist.checked",
                inputSchema: .object(
                    properties: [
                        "title": .string(),
                        "due_at": .string(
                            description:
                                "Reminder due date/time. If timezone is omitted, local time is assumed. Date-only uses local midnight.",
                            format: .dateTime
                        ),
                        "list_name": .string(
                            description: "Reminder list name. Uses default list when omitted."
                        ),
                        "notes": .string(),
                        "priority": .string(
                            default: .string(ReminderPriorityFilter.none.rawValue),
                            enum: ReminderPriorityFilter.allCases.map { .string($0.rawValue) }
                        ),
                        "alarms": .array(
                            description: "Minutes before due date for reminder alarms.",
                            items: .integer()
                        ),
                    ],
                    required: ["title"],
                    additionalProperties: false
                ),
                destructiveHint: true,
                openWorldHint: false
            ) { arguments in
                try await RemindersItemCreateUseCase(
                    runtime: self.runtime,
                    calendar: self.calendar
                )
                .execute(arguments: arguments)
            },
        ]
    }

    func isActivated() async -> Bool {
        runtime.reminderAuthorizationStatus() == .fullAccess
    }

    func activate() async throws {
        try await runtime.requestReminderAccess()
    }
}
