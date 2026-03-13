import Foundation

final class HydrationService {
    private let store: HydrationStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        store: HydrationStore = HydrationStore(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    func status() async throws -> HydrationStatus {
        try makeStatus(from: await store.loadState(), now: now())
    }

    func history(from rawStart: String? = nil, to rawEnd: String? = nil) async throws -> [HydrationEntry] {
        let startDate = try parseOptionalDate(rawStart)
        let endDate = try parseOptionalDate(rawEnd)

        return try await parsedEntries(from: store.loadState())
            .filter { parsed in
                if let startDate, parsed.date < startDate {
                    return false
                }
                if let endDate, parsed.date > endDate {
                    return false
                }
                return true
            }
            .sorted { $0.date < $1.date }
            .map(\.entry)
    }

    func log(
        amountML: Int,
        at rawDate: String? = nil,
        source: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> HydrationStatus {
        guard amountML > 0 else {
            throw HydrationError.invalidAmount
        }

        let intakeDate = try parseOptionalDate(rawDate) ?? now()
        let normalizedSource = normalizeString(source) ?? HydrationDefaults.defaultSource
        let normalizedIdempotencyKey = normalizeString(idempotencyKey)

        var state = try await store.loadState()

        if let normalizedIdempotencyKey,
            state.entries.contains(where: { $0.idempotencyKey == normalizedIdempotencyKey })
        {
            return try makeStatus(from: state, now: now())
        }

        state.entries.append(
            HydrationEntry(
                amountML: amountML,
                at: HydrationDateCoding.storageString(from: intakeDate),
                source: normalizedSource,
                idempotencyKey: normalizedIdempotencyKey
            )
        )

        try await store.saveState(state)
        return try makeStatus(from: state, now: now())
    }

    func setDailyGoal(_ dailyGoalML: Int) async throws -> HydrationStatus {
        guard dailyGoalML > 0 else {
            throw HydrationError.invalidDailyGoal
        }

        var state = try await store.loadState()
        state.dailyGoalML = dailyGoalML
        try await store.saveState(state)
        return try makeStatus(from: state, now: now())
    }

    func setDefaultAmount(_ defaultAmountML: Int) async throws -> HydrationStatus {
        guard defaultAmountML > 0 else {
            throw HydrationError.invalidDefaultAmount
        }

        var state = try await store.loadState()
        state.defaultAmountML = defaultAmountML
        try await store.saveState(state)
        return try makeStatus(from: state, now: now())
    }

    func setNotificationInterval(minutes: Int) async throws -> HydrationStatus {
        guard minutes > 0 else {
            throw HydrationError.invalidNotificationInterval
        }

        var state = try await store.loadState()
        state.notificationIntervalMinutes = minutes
        try await store.saveState(state)
        return try makeStatus(from: state, now: now())
    }

    private func makeStatus(from state: HydrationState, now referenceDate: Date) throws
        -> HydrationStatus
    {
        let parsedEntries = try parsedEntries(from: state)
        let todayEntries = parsedEntries.filter { calendar.isDate($0.date, inSameDayAs: referenceDate) }
        let todayTotalML = todayEntries.reduce(0) { $0 + $1.entry.amountML }
        let remainingML = max(state.dailyGoalML - todayTotalML, 0)
        let lastEntry = parsedEntries.max { $0.date < $1.date }

        let averageThisWeekML = averageDailyIntake(
            for: parsedEntries,
            equalTo: referenceDate,
            byAddingWeeks: 0
        )
        let averageLastWeekML = averageDailyIntake(
            for: parsedEntries,
            equalTo: referenceDate,
            byAddingWeeks: -1
        )

        let projectedEndOfDayML = projectedEndOfDayTotal(
            todayTotalML: todayTotalML,
            referenceDate: referenceDate
        )
        let notificationIntervalSeconds = TimeInterval(state.notificationIntervalMinutes * 60)
        let reminderReferenceDate = lastEntry?.date ?? calendar.startOfDay(for: referenceDate)
        let showTimeToDrinkWarning = reminderReferenceDate < referenceDate.addingTimeInterval(
            -notificationIntervalSeconds
        )
        let nextReminder = reminderPlan(
            todayTotalML: todayTotalML,
            dailyGoalML: state.dailyGoalML,
            notificationIntervalSeconds: notificationIntervalSeconds,
            referenceDate: referenceDate
        )

        return HydrationStatus(
            dailyGoalML: state.dailyGoalML,
            defaultAmountML: state.defaultAmountML,
            notificationIntervalMinutes: state.notificationIntervalMinutes,
            todayTotalML: todayTotalML,
            remainingML: remainingML,
            entriesCountToday: todayEntries.count,
            lastIntakeAt: lastEntry?.entry.at,
            lastAmountML: lastEntry?.entry.amountML,
            progressNormalized: state.dailyGoalML > 0
                ? Double(todayTotalML) / Double(state.dailyGoalML)
                : 0,
            averageThisWeekML: averageThisWeekML,
            averageLastWeekML: averageLastWeekML,
            projectedEndOfDayML: projectedEndOfDayML,
            showTimeToDrinkWarning: showTimeToDrinkWarning,
            showOffTrackWarning: projectedEndOfDayML < Double(state.dailyGoalML),
            nextReminder: nextReminder
        )
    }

    private func parsedEntries(from state: HydrationState) throws -> [(entry: HydrationEntry, date: Date)] {
        try state.entries.map { entry in
            guard let date = HydrationDateCoding.parse(entry.at) else {
                throw HydrationError.invalidStoredDate(entry.id)
            }
            return (entry, date)
        }
    }

    private func averageDailyIntake(
        for entries: [(entry: HydrationEntry, date: Date)],
        equalTo referenceDate: Date,
        byAddingWeeks weekOffset: Int
    ) -> Double {
        guard
            let targetDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: referenceDate)
        else {
            return 0
        }

        let total = entries
            .filter { calendar.isDate($0.date, equalTo: targetDate, toGranularity: .weekOfYear) }
            .reduce(0.0) { partialResult, parsed in
                partialResult + Double(parsed.entry.amountML)
            }

        return total / 7.0
    }

    private func projectedEndOfDayTotal(todayTotalML: Int, referenceDate: Date) -> Double {
        let midnight = calendar.startOfDay(for: referenceDate.addingTimeInterval(24 * 60 * 60))
        let timeUntilMidnight = max(midnight.timeIntervalSince(referenceDate), 0)
        return Double(todayTotalML)
            + (HydrationDefaults.projectedIntakeRateMLPerHour * timeUntilMidnight / 3600.0)
    }

    private func reminderPlan(
        todayTotalML: Int,
        dailyGoalML: Int,
        notificationIntervalSeconds: TimeInterval,
        referenceDate: Date
    ) -> HydrationReminderPlan? {
        let remainingML = dailyGoalML - todayTotalML
        guard remainingML > 0 else {
            return nil
        }

        let midnight = calendar.startOfDay(for: referenceDate.addingTimeInterval(24 * 60 * 60))
        let timeUntilMidnight = max(midnight.timeIntervalSince(referenceDate), 0)
        guard timeUntilMidnight > 0 else {
            return nil
        }

        let heuristicSeconds =
            (HydrationDefaults.projectedIntakeRateMLPerHour * timeUntilMidnight)
            / Double(remainingML)
        let fireIn = min(heuristicSeconds, notificationIntervalSeconds)
        guard fireIn.isFinite, fireIn > 0 else {
            return nil
        }

        let reminderDate = referenceDate.addingTimeInterval(fireIn)
        return HydrationReminderPlan(
            at: HydrationDateCoding.storageString(from: reminderDate),
            inSeconds: max(Int(fireIn.rounded()), 1)
        )
    }

    private func parseOptionalDate(_ rawDate: String?) throws -> Date? {
        guard let normalizedDate = normalizeString(rawDate) else {
            return nil
        }

        guard let parsedDate = HydrationDateCoding.parse(normalizedDate) else {
            throw HydrationError.invalidDate(normalizedDate)
        }

        return parsedDate
    }

    private func normalizeString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
