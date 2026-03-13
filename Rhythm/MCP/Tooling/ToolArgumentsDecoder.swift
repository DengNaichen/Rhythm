import Foundation

struct ToolArgumentsDecoder {
    let arguments: [String: Value]

    func requiredString(_ key: String) throws -> String {
        guard let value = arguments[key] else {
            throw ServiceToolError.missingRequiredArgument(key)
        }

        guard let stringValue = value.stringValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "string")
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServiceToolError.invalidValue(argument: key, reason: "value must not be empty")
        }

        return trimmed
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let stringValue = value.stringValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "string")
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let boolValue = value.boolValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "boolean")
        }

        return boolValue
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let intValue = value.intValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "integer")
        }

        return intValue
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let doubleValue = value.doubleValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "number")
        }

        return doubleValue
    }

    func optionalArray(_ key: String) throws -> [Value]? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let arrayValue = value.arrayValue else {
            throw ServiceToolError.invalidType(argument: key, expected: "array")
        }

        return arrayValue
    }

    func optionalStringArray(_ key: String) throws -> [String]? {
        guard let values = try optionalArray(key) else {
            return nil
        }

        return try values.enumerated().compactMap { index, value in
            guard let stringValue = value.stringValue else {
                throw ServiceToolError.invalidType(
                    argument: "\(key)[\(index)]",
                    expected: "string"
                )
            }

            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    func enumValue<T: RawRepresentable & CaseIterable>(
        for key: String,
        default defaultValue: T? = nil
    ) throws -> T where T.RawValue == String {
        if let value = try optionalEnumValue(for: key, as: T.self) {
            return value
        }

        if let defaultValue {
            return defaultValue
        }

        throw ServiceToolError.missingRequiredArgument(key)
    }

    func optionalEnumValue<T: RawRepresentable & CaseIterable>(
        for key: String,
        as type: T.Type = T.self
    ) throws -> T? where T.RawValue == String {
        guard let rawValue = try optionalString(key) else {
            return nil
        }

        guard let enumValue = T(rawValue: rawValue) else {
            throw ServiceToolError.unsupportedEnum(
                argument: key,
                value: rawValue,
                allowed: T.allCases.map(\.rawValue).sorted()
            )
        }

        return enumValue
    }
}
