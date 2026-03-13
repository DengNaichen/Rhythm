import Foundation

nonisolated struct HydrationReminderPlan: Codable, Equatable, Sendable {
    var at: String
    var inSeconds: Int

    init(at: String, inSeconds: Int) {
        self.at = at
        self.inSeconds = inSeconds
    }
}
