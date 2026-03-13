import Foundation

enum SettingsMetrics {
    static let sidebarWidth: Double = 200
    static let windowWidth: Double = 900
    static let windowHeight: Double = 620
}

enum SettingsStorageKey {
    static let selectedSection = "settings.selectedSection"
}

enum SettingsSection: Hashable, Identifiable {
    case general
    case service(ServiceID)
    case about

    init(storageValue: String) {
        switch storageValue {
        case "general":
            self = .general
        case "about":
            self = .about
        case let value where value.hasPrefix("service:"):
            let rawValue = String(value.dropFirst("service:".count))
            if let serviceID = ServiceID(rawValue: rawValue) {
                self = .service(serviceID)
            } else {
                self = .general
            }
        default:
            self = .general
        }
    }

    var id: String {
        storageValue
    }

    var storageValue: String {
        switch self {
        case .general:
            "general"
        case .service(let serviceID):
            "service:\(serviceID.rawValue)"
        case .about:
            "about"
        }
    }
}
