import Foundation

nonisolated enum HydrationError: Error, LocalizedError, Sendable {
    case invalidAmount
    case invalidDailyGoal
    case invalidDefaultAmount
    case invalidNotificationInterval
    case invalidDate(String)
    case invalidStoredDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Water amount must be a positive integer."
        case .invalidDailyGoal:
            return "Daily goal must be a positive integer."
        case .invalidDefaultAmount:
            return "Default amount must be a positive integer."
        case .invalidNotificationInterval:
            return "Notification interval must be a positive integer."
        case let .invalidDate(value):
            return "Invalid date: \(value)"
        case let .invalidStoredDate(entryID):
            return "Stored hydration entry has an invalid date: \(entryID)"
        }
    }
}
