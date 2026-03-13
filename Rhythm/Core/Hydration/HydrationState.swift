import Foundation

nonisolated enum HydrationDefaults {
    static let schemaVersion = 1
    static let dailyGoalML = 2_000
    static let defaultAmountML = 250
    static let notificationIntervalMinutes = 60
    static let defaultSource = "manual"
    static let projectedIntakeRateMLPerHour = 200.0
}

nonisolated struct HydrationState: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var dailyGoalML: Int
    var defaultAmountML: Int
    var notificationIntervalMinutes: Int
    var entries: [HydrationEntry]

    init(
        schemaVersion: Int = HydrationDefaults.schemaVersion,
        dailyGoalML: Int = HydrationDefaults.dailyGoalML,
        defaultAmountML: Int = HydrationDefaults.defaultAmountML,
        notificationIntervalMinutes: Int = HydrationDefaults.notificationIntervalMinutes,
        entries: [HydrationEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.dailyGoalML = dailyGoalML
        self.defaultAmountML = defaultAmountML
        self.notificationIntervalMinutes = notificationIntervalMinutes
        self.entries = entries
    }

    static let defaultState = HydrationState()
}
