import Foundation

nonisolated struct HydrationEntry: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var amountML: Int
  var at: String
  var source: String
  var idempotencyKey: String?

  init(
    id: String = UUID().uuidString,
    amountML: Int,
    at: String,
    source: String,
    idempotencyKey: String? = nil
  ) {
    self.id = id
    self.amountML = amountML
    self.at = at
    self.source = source
    self.idempotencyKey = idempotencyKey
  }
}
