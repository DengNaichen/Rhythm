import Foundation

extension ISO8601DateFormatter {
    nonisolated static func lenientDate(fromISO8601String dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()

        let optionsToTry: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate, .withFullTime, .withFractionalSeconds],
            [.withFullDate, .withFullTime],
            [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime, .withFractionalSeconds],
            [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime],
        ]

        for options in optionsToTry {
            formatter.formatOptions = options
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        let hasTimeZoneInfo =
            dateString.range(
                of: #"([Zz]|[+-]\d{2}(:?\d{2})?)$"#,
                options: .regularExpression
            ) != nil
        guard !hasTimeZoneInfo else {
            return nil
        }

        let fallbackFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.timeZone = TimeZone.current

        for format in fallbackFormats {
            fallbackFormatter.dateFormat = format
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    nonisolated static func parsedLenientISO8601Date(
        fromISO8601String dateString: String
    ) -> (date: Date, isDateOnly: Bool)? {
        let isDateOnly = isDateOnlyISO8601String(dateString)
        guard let date = lenientDate(fromISO8601String: dateString) else {
            return nil
        }
        return (date, isDateOnly)
    }

    nonisolated static func isDateOnlyISO8601String(_ dateString: String) -> Bool {
        dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

extension Calendar {
    nonisolated func normalizedStartDate(from date: Date, isDateOnly: Bool) -> Date {
        isDateOnly ? startOfDay(for: date) : date
    }

    nonisolated func normalizedEndDate(from date: Date, isDateOnly: Bool) -> Date {
        guard isDateOnly else { return date }
        let startOfDay = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
    }
}
