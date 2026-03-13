import Foundation

enum SettingSection: String, CaseIterable, Identifiable {
    case general = "General"
    case calendar = "Calendar"
    case reminders = "Reminders"
    case things = "Things"
    case hydration = "Hydration"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gear"
        case .calendar:
            return "calendar"
        case .reminders:
            return "list.bullet"
        case .things:
            return "checklist"
        case .hydration:
            return "drop.fill"
        case .about:
            return "info.circle"
        }
    }
}
