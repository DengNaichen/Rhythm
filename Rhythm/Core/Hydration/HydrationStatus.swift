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
}
