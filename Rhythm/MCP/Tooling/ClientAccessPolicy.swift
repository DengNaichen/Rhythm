import Foundation

nonisolated enum ClientAccessStorageKey {
  static let allowClaudeDesktop = "clientAccess.allowClaudeDesktop"
  static let allowOpenClaw = "clientAccess.allowOpenClaw"
  static let allowUnknownClients = "clientAccess.allowUnknownClients"
}

nonisolated enum KnownClient: String, CaseIterable, Identifiable {
  case claudeDesktop
  case openClaw

  var id: String { rawValue }

  var title: String {
    switch self {
    case .claudeDesktop:
      return "Claude Desktop"
    case .openClaw:
      return "OpenClaw"
    }
  }

  var storageKey: String {
    switch self {
    case .claudeDesktop:
      return ClientAccessStorageKey.allowClaudeDesktop
    case .openClaw:
      return ClientAccessStorageKey.allowOpenClaw
    }
  }

  var defaultValue: Bool { true }

  var normalizedNames: Set<String> {
    switch self {
    case .claudeDesktop:
      return ["claudedesktop", "claudeai", "claude"]
    case .openClaw:
      return ["openclaw"]
    }
  }

  static var defaultAllowances: [KnownClient: Bool] {
    Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultValue) })
  }

  static func matching(_ clientName: String) -> Self? {
    let normalizedName = normalizedClientName(clientName)
    return allCases.first { $0.normalizedNames.contains(normalizedName) }
  }
}

nonisolated func normalizedClientName(_ clientName: String) -> String {
  String(
    clientName
      .lowercased()
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
  )
}

nonisolated struct ClientAccessPolicy: Equatable {
  var knownClients: [KnownClient: Bool]
  var allowUnknownClients: Bool

  init(
    knownClients: [KnownClient: Bool] = KnownClient.defaultAllowances,
    allowUnknownClients: Bool = false
  ) {
    self.knownClients = knownClients
    self.allowUnknownClients = allowUnknownClients
  }

  func allows(_ clientName: String) -> Bool {
    if let knownClient = KnownClient.matching(clientName) {
      return allows(knownClient)
    }

    return allowUnknownClients
  }

  func allows(_ client: KnownClient) -> Bool {
    knownClients[client] ?? client.defaultValue
  }

  mutating func setAllowed(_ allowed: Bool, for client: KnownClient) {
    knownClients[client] = allowed
  }
}
