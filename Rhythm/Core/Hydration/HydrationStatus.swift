import Foundation

nonisolated struct HydrationStatus: Codable, Equatable, Sendable {
    var dailyGoalML: Int
    var defaultAmountML: Int
    var notificationIntervalMinutes: Int
    var todayTotalML: Int
    var remainingML: Int
    var entriesCountToday: Int
    var lastIntakeAt: String?
    var lastAmountML: Int?
    var progressNormalized: Double
    var averageThisWeekML: Double
    var averageLastWeekML: Double
    var projectedEndOfDayML: Double
    var showTimeToDrinkWarning: Bool
    var showOffTrackWarning: Bool
    var nextReminder: HydrationReminderPlan?

    init(
        dailyGoalML: Int,
        defaultAmountML: Int,
        notificationIntervalMinutes: Int,
        todayTotalML: Int,
        remainingML: Int,
        entriesCountToday: Int,
        lastIntakeAt: String?,
        lastAmountML: Int?,
        progressNormalized: Double,
        averageThisWeekML: Double,
        averageLastWeekML: Double,
        projectedEndOfDayML: Double,
        showTimeToDrinkWarning: Bool,
        showOffTrackWarning: Bool,
        nextReminder: HydrationReminderPlan?
    ) {
        self.dailyGoalML = dailyGoalML
        self.defaultAmountML = defaultAmountML
        self.notificationIntervalMinutes = notificationIntervalMinutes
        self.todayTotalML = todayTotalML
        self.remainingML = remainingML
        self.entriesCountToday = entriesCountToday
        self.lastIntakeAt = lastIntakeAt
        self.lastAmountML = lastAmountML
        self.progressNormalized = progressNormalized
        self.averageThisWeekML = averageThisWeekML
        self.averageLastWeekML = averageLastWeekML
        self.projectedEndOfDayML = projectedEndOfDayML
        self.showTimeToDrinkWarning = showTimeToDrinkWarning
        self.showOffTrackWarning = showOffTrackWarning
        self.nextReminder = nextReminder
    }
}
