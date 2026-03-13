import EventKit

extension EKEventAvailability {
    nonisolated init(_ string: String) {
        switch string.lowercased() {
        case "busy":
            self = .busy
        case "free":
            self = .free
        case "tentative":
            self = .tentative
        case "unavailable":
            self = .unavailable
        default:
            self = .busy
        }
    }

    nonisolated var stringValue: String {
        switch self {
        case .busy:
            return "busy"
        case .free:
            return "free"
        case .tentative:
            return "tentative"
        case .unavailable:
            return "unavailable"
        default:
            return "unknown"
        }
    }
}

extension EKEventStatus {
    nonisolated var mcpStatusValue: String {
        switch self {
        case .none:
            return "none"
        case .tentative:
            return "tentative"
        case .confirmed:
            return "confirmed"
        case .canceled:
            return "canceled"
        @unknown default:
            return "none"
        }
    }
}

extension EKReminderPriority {
    nonisolated static func from(string: String) -> EKReminderPriority {
        switch string.lowercased() {
        case "high":
            return .high
        case "medium":
            return .medium
        case "low":
            return .low
        default:
            return .none
        }
    }
}

extension Int {
    nonisolated var mcpPriorityValue: String {
        switch self {
        case Int(EKReminderPriority.high.rawValue):
            return "high"
        case Int(EKReminderPriority.medium.rawValue):
            return "medium"
        case Int(EKReminderPriority.low.rawValue):
            return "low"
        default:
            return "none"
        }
    }
}
