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
        case let .unauthorized(service):
            return "\(service) access not authorized"
        case let .missingRequiredArgument(name):
            return "Missing required argument: \(name)"
        case let .invalidType(argument, expected):
            return "Invalid type for \(argument): expected \(expected)"
        case let .invalidValue(argument, reason):
            return "Invalid value for \(argument): \(reason)"
        case let .invalidDate(argument, value):
            return "Invalid date for \(argument): \(value)"
        case let .invalidURL(argument, value):
            return "Invalid URL for \(argument): \(value)"
        case let .unsupportedEnum(argument, value, allowed):
            return "Invalid value for \(argument): \(value). Allowed values: \(allowed.joined(separator: ", "))"
        }
    }
}
