import Foundation

enum ServiceToolError: Error, LocalizedError, Equatable {
  case unauthorized(service: String)
  case missingRequiredArgument(String)
  case invalidType(argument: String, expected: String)
  case invalidValue(argument: String, reason: String)
  case invalidDate(argument: String, value: String)
  case invalidURL(argument: String, value: String)
  case unsupportedEnum(argument: String, value: String, allowed: [String])

  var errorDescription: String? {
    switch self {
    case .unauthorized(let service):
      return "\(service) access not authorized"
    case .missingRequiredArgument(let name):
      return "Missing required argument: \(name)"
    case .invalidType(let argument, let expected):
      return "Invalid type for \(argument): expected \(expected)"
    case .invalidValue(let argument, let reason):
      return "Invalid value for \(argument): \(reason)"
    case .invalidDate(let argument, let value):
      return "Invalid date for \(argument): \(value)"
    case .invalidURL(let argument, let value):
      return "Invalid URL for \(argument): \(value)"
    case .unsupportedEnum(let argument, let value, let allowed):
      return
        "Invalid value for \(argument): \(value). Allowed values: \(allowed.joined(separator: ", "))"
    }
  }
}
