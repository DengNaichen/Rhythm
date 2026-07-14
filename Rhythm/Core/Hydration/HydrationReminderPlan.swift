import Foundation

nonisolated struct HydrationReminderPlan: Codable, Equatable, Sendable {
  var at: String
  var inSeconds: Int
}
