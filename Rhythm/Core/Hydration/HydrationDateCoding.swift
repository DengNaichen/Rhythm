import Foundation

nonisolated enum HydrationDateCoding {
    static func parse(_ dateString: String) -> Date? {
        ISO8601DateFormatter.lenientDate(fromISO8601String: dateString)
    }

    static func storageString(from date: Date) -> String {
        storageFormatter.string(from: date)
    }

    private static let storageFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
