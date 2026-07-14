import SwiftUI

enum ServiceStorageKey {
  static let calendarEnabled = "calendarEnabled"
  static let hydrationEnabled = "hydrationEnabled"
  static let thingsEnabled = "thingsEnabled"
}
enum ServiceID: String, CaseIterable, Identifiable, Sendable {
  case calendar
  case hydration
  case things

  var id: String {
    rawValue
  }

  var storageKey: String {
    switch self {
    case .calendar:
      ServiceStorageKey.calendarEnabled
    case .hydration:
      ServiceStorageKey.hydrationEnabled
    case .things:
      ServiceStorageKey.thingsEnabled
    }
  }
}

struct ServiceConfig: Identifiable {
  let id: ServiceID
  let name: String
  let iconName: String
  let color: Color
  let service: any Service
}
