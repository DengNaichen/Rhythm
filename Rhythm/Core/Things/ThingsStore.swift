import Foundation

protocol ThingsDatabaseAccessing: AnyObject {
  func withReadableDatabaseURL<T>(_ operation: (URL) throws -> T) throws -> T
}

enum ThingsDatabaseError: Error, LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case bindFailed(String)
  case stepFailed(String)

  var errorDescription: String? {
    switch self {
    case .openFailed(let message):
      return "Failed to open Things database: \(message)"
    case .prepareFailed(let message):
      return "Failed to prepare Things database query: \(message)"
    case .bindFailed(let message):
      return "Failed to bind Things database query: \(message)"
    case .stepFailed(let message):
      return "Failed to read from Things database: \(message)"
    }
  }
}

final class ThingsStore: ThingsRepository {
  let databaseAccess: any ThingsDatabaseAccessing
  let calendar: Calendar
  let now: () -> Date

  init(
    databaseAccess: any ThingsDatabaseAccessing,
    calendar: Calendar = .current,
    now: @escaping () -> Date = Date.init
  ) {
    self.databaseAccess = databaseAccess
    self.calendar = calendar
    self.now = now
  }
}
