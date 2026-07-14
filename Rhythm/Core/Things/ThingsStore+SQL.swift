import Foundation

extension ThingsStore {
  static let todoEffectiveTrashedExpression = """
    (
      TASK.trashed != 0
      OR IFNULL(HEADING.trashed, 0) != 0
      OR IFNULL(PROJECT.trashed, 0) != 0
      OR IFNULL(HEADING_PROJECT.trashed, 0) != 0
    )
    """

  static func thingsDate(for date: Date, calendar: Calendar) -> Int {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return ((components.year ?? 0) << 16)
      | ((components.month ?? 0) << 12)
      | ((components.day ?? 0) << 7)
  }

  static func thingsTimeToISOTimeExpression(column: String) -> String {
    let hourMask = 0x7C00_0000
    let minuteMask = 0x03F0_0000
    return """
      CASE
        WHEN \(column) IS NOT NULL THEN printf(
          '%02d:%02d',
          (\(column) & \(hourMask)) >> 26,
          (\(column) & \(minuteMask)) >> 20
        )
        ELSE NULL
      END
      """
  }

  static func reminderDateTimeExpression(
    dateColumn: String,
    timeColumn: String
  ) -> String {
    return """
      CASE
        WHEN \(dateColumn) IS NOT NULL AND \(timeColumn) IS NOT NULL THEN
          \(thingsDateToISODateExpression(column: dateColumn))
          || 'T' || \(thingsTimeToISOTimeExpression(column: timeColumn)) || ':00'
        ELSE NULL
      END
      """
  }

  static func reminderSortExpression(dateColumn: String, timeColumn: String) -> String {
    return """
      CASE
        WHEN \(dateColumn) IS NOT NULL AND \(timeColumn) IS NOT NULL THEN
          CAST(\(dateColumn) AS INTEGER) * 2147483648 + CAST(\(timeColumn) AS INTEGER)
        ELSE NULL
      END
      """
  }

  static func thingsDateToISODateExpression(column: String) -> String {
    let yearMask = 0b111_11111111_00000000_00000000
    let monthMask = 0b000_00000000_11110000_00000000
    let dayMask = 0b000_00000000_00001111_10000000
    let year = "(\(column) & \(yearMask)) >> 16"
    let month = "(\(column) & \(monthMask)) >> 12"
    let day = "(\(column) & \(dayMask)) >> 7"
    return """
      CASE
          WHEN \(column) THEN printf('%d-%02d-%02d', \(year), \(month), \(day))
          ELSE \(column)
      END
      """
  }
}
