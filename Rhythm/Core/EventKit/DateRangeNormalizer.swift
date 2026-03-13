import Foundation

nonisolated struct DateRange: Equatable, Sendable {
    let from: Date
    let to: Date
}

nonisolated struct OptionalDateRange: Equatable, Sendable {
    let from: Date?
    let to: Date?
}

nonisolated enum DateRangeNormalizer {
    static func normalizeCalendarRange(
        from rawFrom: String?,
        to rawTo: String?,
        now: () -> Date = { Date() },
        calendar: Calendar = .current
    ) throws -> DateRange {
        let parsedFrom = try parse(rawFrom, argument: "from")
        let parsedTo = try parse(rawTo, argument: "to")

        var fromDate = parsedFrom?.date ?? now()
        var toDate = parsedTo?.date
            ?? calendar.date(byAdding: .weekOfYear, value: 1, to: fromDate)
            ?? fromDate

        var fromIsDateOnly = parsedFrom?.isDateOnly ?? false
        let toIsDateOnly = parsedTo?.isDateOnly ?? false

        if parsedFrom == nil, let parsedTo, parsedTo.isDateOnly {
            fromDate = parsedTo.date
            fromIsDateOnly = true
        }

        fromDate = calendar.normalizedStartDate(from: fromDate, isDateOnly: fromIsDateOnly)

        if toIsDateOnly {
            toDate = calendar.normalizedEndDate(from: toDate, isDateOnly: true)
        } else if parsedTo == nil {
            if fromIsDateOnly {
                toDate = calendar.normalizedEndDate(from: fromDate, isDateOnly: true)
            } else {
                toDate = calendar.date(byAdding: .weekOfYear, value: 1, to: fromDate) ?? toDate
            }
        }

        guard toDate >= fromDate else {
            throw ServiceToolError.invalidValue(
                argument: "to",
                reason: "'to' must be later than or equal to 'from'"
            )
        }

        return DateRange(from: fromDate, to: toDate)
    }

    static func normalizeOptionalRange(
        from rawFrom: String?,
        to rawTo: String?,
        calendar: Calendar = .current
    ) throws -> OptionalDateRange {
        let parsedFrom = try parse(rawFrom, argument: "from")
        let parsedTo = try parse(rawTo, argument: "to")

        let fromDate = parsedFrom.map {
            calendar.normalizedStartDate(from: $0.date, isDateOnly: $0.isDateOnly)
        }
        let toDate = parsedTo.map {
            calendar.normalizedEndDate(from: $0.date, isDateOnly: $0.isDateOnly)
        }

        if let fromDate, let toDate, toDate < fromDate {
            throw ServiceToolError.invalidValue(
                argument: "to",
                reason: "'to' must be later than or equal to 'from'"
            )
        }

        return OptionalDateRange(from: fromDate, to: toDate)
    }

    static func normalizeSingleDate(
        _ rawValue: String,
        argument: String,
        calendar: Calendar = .current
    ) throws -> Date {
        let parsed = try parse(rawValue, argument: argument)
        guard let parsed else {
            throw ServiceToolError.missingRequiredArgument(argument)
        }

        return calendar.normalizedStartDate(from: parsed.date, isDateOnly: parsed.isDateOnly)
    }

    static func parse(
        _ rawValue: String?,
        argument: String
    ) throws -> (date: Date, isDateOnly: Bool)? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard
            let parsed = ISO8601DateFormatter.parsedLenientISO8601Date(
                fromISO8601String: trimmed
            )
        else {
            throw ServiceToolError.invalidDate(argument: argument, value: trimmed)
        }

        return parsed
    }
}
