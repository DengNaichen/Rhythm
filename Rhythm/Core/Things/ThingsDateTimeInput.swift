import Foundation

nonisolated enum ThingsDateTimeInput {
  static func date(_ value: String, calendar: Calendar) -> Date? {
    let formatter = localFormatter(format: "yyyy-MM-dd", calendar: calendar)
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
      return nil
    }
    return date
  }

  static func timestamp(_ value: String, upperBound: Bool, calendar: Calendar) -> Date? {
    if let date = rfc3339Date(value) { return date }

    let normalized = value.replacingOccurrences(of: "T", with: " ")
    let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
    for format in formats {
      let formatter = localFormatter(format: format, calendar: calendar)
      guard
        let date = formatter.date(from: normalized),
        formatter.string(from: date) == normalized
      else { continue }

      guard upperBound else { return date }
      switch format {
      case "yyyy-MM-dd":
        return calendar.date(byAdding: .day, value: 1, to: date)?.addingTimeInterval(-1)
      case "yyyy-MM-dd HH:mm":
        return date.addingTimeInterval(59)
      default:
        return date
      }
    }
    return nil
  }

  static func reminder(_ value: String, upperBound: Bool, calendar: Calendar) -> Date? {
    if let date = rfc3339Date(value) { return date }

    let normalized = value.replacingOccurrences(of: " ", with: "T")
    let formatter = localFormatter(format: "yyyy-MM-dd'T'HH:mm", calendar: calendar)
    guard
      let date = formatter.date(from: normalized),
      formatter.string(from: date) == normalized
    else { return nil }
    return upperBound ? date.addingTimeInterval(59) : date
  }

  static func localTimestamp(_ date: Date, calendar: Calendar, separator: String) -> String {
    localFormatter(
      format: "yyyy-MM-dd'\(separator)'HH:mm:ss",
      calendar: calendar
    ).string(from: date)
  }

  private static func rfc3339Date(_ value: String) -> Date? {
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let date = standard.date(from: value) { return date }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value)
  }

  private static func localFormatter(format: String, calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter
  }
}
