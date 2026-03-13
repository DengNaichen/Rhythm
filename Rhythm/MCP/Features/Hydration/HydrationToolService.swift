import Foundation
import JSONSchema
import OrderedCollections

private enum HydrationAction: String {
    case status
    case log
}

private struct HydrationReminderPlanPayload: Encodable {
    let at: String
    let inSeconds: Int

    enum CodingKeys: String, CodingKey {
        case at
        case inSeconds = "in_seconds"
    }

    nonisolated init(_ reminder: HydrationReminderPlan) {
        at = reminder.at
        inSeconds = reminder.inSeconds
    }
}

private struct HydrationEntryPayload: Encodable {
    let id: String
    let amountML: Int
    let at: String
    let source: String
    let idempotencyKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case amountML = "amount_ml"
        case at
        case source
        case idempotencyKey = "idempotency_key"
    }

    nonisolated init(_ entry: HydrationEntry) {
        id = entry.id
        amountML = entry.amountML
        at = entry.at
        source = entry.source
        idempotencyKey = entry.idempotencyKey
    }
}

private struct HydrationStatusPayload: Encodable {
    let dailyGoalML: Int
    let defaultAmountML: Int
    let notificationIntervalMinutes: Int
    let todayTotalML: Int
    let remainingML: Int
    let entriesCountToday: Int
    let lastIntakeAt: String?
    let lastAmountML: Int?
    let progressNormalized: Double
    let averageThisWeekML: Double
    let averageLastWeekML: Double
    let projectedEndOfDayML: Double
    let showTimeToDrinkWarning: Bool
    let showOffTrackWarning: Bool
    let nextReminder: HydrationReminderPlanPayload?

    enum CodingKeys: String, CodingKey {
        case dailyGoalML = "daily_goal_ml"
        case defaultAmountML = "default_amount_ml"
        case notificationIntervalMinutes = "notification_interval_minutes"
        case todayTotalML = "today_total_ml"
        case remainingML = "remaining_ml"
        case entriesCountToday = "entries_count_today"
        case lastIntakeAt = "last_intake_at"
        case lastAmountML = "last_amount_ml"
        case progressNormalized = "progress_normalized"
        case averageThisWeekML = "average_this_week_ml"
        case averageLastWeekML = "average_last_week_ml"
        case projectedEndOfDayML = "projected_end_of_day_ml"
        case showTimeToDrinkWarning = "show_time_to_drink_warning"
        case showOffTrackWarning = "show_off_track_warning"
        case nextReminder = "next_reminder"
    }

    nonisolated init(_ status: HydrationStatus) {
        dailyGoalML = status.dailyGoalML
        defaultAmountML = status.defaultAmountML
        notificationIntervalMinutes = status.notificationIntervalMinutes
        todayTotalML = status.todayTotalML
        remainingML = status.remainingML
        entriesCountToday = status.entriesCountToday
        lastIntakeAt = status.lastIntakeAt
        lastAmountML = status.lastAmountML
        progressNormalized = status.progressNormalized
        averageThisWeekML = status.averageThisWeekML
        averageLastWeekML = status.averageLastWeekML
        projectedEndOfDayML = status.projectedEndOfDayML
        showTimeToDrinkWarning = status.showTimeToDrinkWarning
        showOffTrackWarning = status.showOffTrackWarning
        nextReminder = status.nextReminder.map(HydrationReminderPlanPayload.init)
    }
}

enum HydrationToolServiceError: Error, LocalizedError {
    case unknownAction(String)
    case missingRequiredArgument(String)
    case invalidType(String, expected: String)

    var errorDescription: String? {
        switch self {
        case let .unknownAction(action):
            return "Unknown hydration action: \(action)"
        case let .missingRequiredArgument(name):
            return "Missing required argument: \(name)"
        case let .invalidType(name, expected):
            return "Invalid type for \(name): expected \(expected)"
        }
    }
}

@MainActor
final class HydrationToolService: Service {
    let id = "hydration"
    let displayName = "Hydration"

    private let core: HydrationService

    init(core: HydrationService) {
        self.core = core
    }

    convenience init() {
        self.init(core: HydrationService())
    }

    func tools() -> [Tool] {
        [
            Tool(
                name: "hydration",
                title: "Hydration",
                description: "Read hydration status or log water intake.",
                systemImage: "drop",
                inputSchema: .object(
                    properties: [
                        "action": .string(
                            description: "Hydration action to perform",
                            enum: [.string(HydrationAction.status.rawValue), .string(HydrationAction.log.rawValue)]
                        ),
                        "amount_ml": .integer(
                            description: "Water amount in milliliters for log actions",
                            minimum: 1
                        ),
                        "at": .string(
                            description:
                                "Optional intake timestamp. Accepts ISO 8601 with or without timezone; local time is assumed when omitted."
                        ),
                        "idempotency_key": .string(
                            description: "Optional key to de-duplicate repeated log calls"
                        ),
                        "source": .string(
                            description: "Optional source label for the hydration entry"
                        ),
                    ],
                    required: ["action"],
                    additionalProperties: false
                ),
                idempotentHint: false,
                openWorldHint: false
            ) { arguments in
                let action = try self.requiredAction(in: arguments)

                switch action {
                case .status:
                    return HydrationStatusPayload(try await self.core.status())
                case .log:
                    return HydrationStatusPayload(
                        try await self.core.log(
                            amountML: try self.requiredPositiveInt("amount_ml", in: arguments),
                            at: try self.optionalString("at", in: arguments),
                            source: try self.optionalString("source", in: arguments),
                            idempotencyKey: try self.optionalString("idempotency_key", in: arguments)
                        )
                    )
                }
            },
            Tool(
                name: "hydration_history",
                title: "Hydration History",
                description: "List hydration entries optionally filtered by time range.",
                systemImage: "clock.arrow.circlepath",
                inputSchema: .object(
                    properties: [
                        "from": .string(description: "Optional inclusive start timestamp in ISO 8601 format."),
                        "to": .string(description: "Optional inclusive end timestamp in ISO 8601 format."),
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await self.core.history(
                    from: try self.optionalString("from", in: arguments),
                    to: try self.optionalString("to", in: arguments)
                )
                .map(HydrationEntryPayload.init)
            },
            Tool(
                name: "hydration_set_goal",
                title: "Set Hydration Goal",
                description: "Set the daily hydration goal in milliliters.",
                systemImage: "target",
                inputSchema: .object(
                    properties: [
                        "daily_goal_ml": .integer(
                            description: "Daily hydration goal in milliliters.",
                            minimum: 1
                        )
                    ],
                    required: ["daily_goal_ml"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ) { arguments in
                HydrationStatusPayload(
                    try await self.core.setDailyGoal(
                        try self.requiredPositiveInt("daily_goal_ml", in: arguments)
                    )
                )
            },
            Tool(
                name: "hydration_set_default_amount",
                title: "Set Default Amount",
                description: "Set the default hydration log amount in milliliters.",
                systemImage: "drop.fill",
                inputSchema: .object(
                    properties: [
                        "default_amount_ml": .integer(
                            description: "Default hydration log amount in milliliters.",
                            minimum: 1
                        )
                    ],
                    required: ["default_amount_ml"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ) { arguments in
                HydrationStatusPayload(
                    try await self.core.setDefaultAmount(
                        try self.requiredPositiveInt("default_amount_ml", in: arguments)
                    )
                )
            },
            Tool(
                name: "hydration_set_notification_interval",
                title: "Set Hydration Reminder Interval",
                description: "Set the hydration reminder interval in minutes.",
                systemImage: "bell",
                inputSchema: .object(
                    properties: [
                        "notification_interval_minutes": .integer(
                            description: "Reminder interval in minutes.",
                            minimum: 1
                        )
                    ],
                    required: ["notification_interval_minutes"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ) { arguments in
                HydrationStatusPayload(
                    try await self.core.setNotificationInterval(
                        minutes: try self.requiredPositiveInt(
                            "notification_interval_minutes",
                            in: arguments
                        )
                    )
                )
            },
        ]
    }

    func status() async throws -> HydrationStatus {
        try await core.status()
    }

    func updatePreferences(
        dailyGoalML: Int,
        defaultAmountML: Int,
        notificationIntervalMinutes: Int
    ) async throws -> HydrationStatus {
        _ = try await core.setDailyGoal(dailyGoalML)
        _ = try await core.setDefaultAmount(defaultAmountML)
        return try await core.setNotificationInterval(minutes: notificationIntervalMinutes)
    }

    private func requiredAction(in arguments: [String: Value]) throws -> HydrationAction {
        let rawValue = try requiredString("action", in: arguments)
        guard let action = HydrationAction(rawValue: rawValue) else {
            throw HydrationToolServiceError.unknownAction(rawValue)
        }
        return action
    }

    private func requiredPositiveInt(_ key: String, in arguments: [String: Value]) throws -> Int {
        guard let value = arguments[key] else {
            throw HydrationToolServiceError.missingRequiredArgument(key)
        }

        guard let intValue = value.intValue else {
            throw HydrationToolServiceError.invalidType(key, expected: "integer")
        }

        guard intValue > 0 else {
            throw HydrationError.invalidAmount
        }

        return intValue
    }

    private func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
        guard let value = arguments[key] else {
            throw HydrationToolServiceError.missingRequiredArgument(key)
        }

        guard let stringValue = value.stringValue else {
            throw HydrationToolServiceError.invalidType(key, expected: "string")
        }

        return stringValue
    }

    private func optionalString(_ key: String, in arguments: [String: Value]) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let stringValue = value.stringValue else {
            throw HydrationToolServiceError.invalidType(key, expected: "string")
        }

        return stringValue
    }
}
