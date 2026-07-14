import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func showTool() -> Tool {
    Tool(
      name: "things_show",
      title: "Show in Things",
      description: "Open a todo, project, area, tag, or built-in list in the Things app.",
      systemImage: "arrow.up.forward.square",
      inputSchema: .object(
        properties: [
          "target": .string(
            description:
              "Entity reference, raw ID, unique exact title, or supported built-in ID: inbox, today, tomorrow, upcoming, anytime, someday, deadlines, logbook, repeating, all-projects, or logged-projects."
          ),
          "quick_find": .boolean(
            description:
              "Pass target to Things Quick Find and open its first result instead of resolving locally.",
            default: false
          ),
          "filter_tags": .array(
            description: "Optional tag filters for the shown list.", items: .string()),
        ],
        required: ["target"],
        additionalProperties: false
      ),
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    ) { arguments in
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      let target = try decoder.requiredString("target")
      let filterTags = try decoder.optionalStringArray("filter_tags")
      try self.validateJoinedURLValues(filterTags, key: "filter_tags", separator: ",")
      let quickFind = try decoder.optionalBool("quick_find") ?? false
      let parsedTarget = ThingsEntityID.parse(target)
      if parsedTarget.kind == .heading {
        throw ThingsServiceError.invalidValue(
          "target", reason: "Things show URLs do not support headings; show the parent project")
      }
      if quickFind {
        if parsedTarget.kind != nil || self.looksLikeThingsID(target) {
          throw ThingsServiceError.invalidValue(
            "target",
            reason: "typed references and raw IDs require quick_find=false"
          )
        }
        try await self.activate()
        if let resolved = try? self.repository.resolveShowTarget(target) {
          let kind = ThingsEntityID.parse(resolved.id).kind
          if kind == .todo {
            throw ThingsServiceError.invalidValue(
              "target",
              reason: "Things Quick Find URLs cannot show todos; use quick_find=false"
            )
          }
          if kind == .heading {
            throw ThingsServiceError.invalidValue(
              "target",
              reason: "Things show URLs do not support headings; show the parent project"
            )
          }
        }
        let callback = try await self.callbackExecutor.execute(
          try self.urlBuilder.showURL(
            query: target,
            filterTags: filterTags,
            callbacks: nil
          ))
        return ThingsNavigationResult(
          action: "show",
          target: target,
          confirmed: true,
          parameters: callback.parameters,
          message: "Things Quick Find navigation confirmed."
        )
      }
      let lowercased = target.lowercased()
      let builtinNames = Set(ThingsShowList.allCases.map(\.rawValue))

      let reference: ThingsReference
      if builtinNames.contains(lowercased) {
        reference = ThingsReference(
          id: lowercased,
          title: lowercased.replacingOccurrences(of: "-", with: " ").capitalized
        )
      } else if parsedTarget.kind != nil {
        reference = ThingsReference(id: target, title: target)
      } else {
        try await self.activate()
        reference = try self.repository.resolveShowTarget(target)
      }
      if ThingsEntityID.parse(reference.id).kind == .heading {
        throw ThingsServiceError.invalidValue(
          "target", reason: "Things show URLs do not support headings; show the parent project")
      }
      if ThingsEntityID.parse(reference.id).kind == .todo, filterTags?.isEmpty == false {
        throw ThingsServiceError.invalidValue(
          "filter_tags", reason: "Things ignores tag filters when showing a single todo")
      }

      let callback = try await self.callbackExecutor.execute(
        try self.urlBuilder.showURL(
          id: reference.id,
          filterTags: filterTags,
          callbacks: nil
        ))
      return ThingsNavigationResult(
        action: "show",
        target: reference.id,
        confirmed: true,
        parameters: callback.parameters,
        message: "Things navigation confirmed."
      )
    }
  }

  func openSearchTool() -> Tool {
    Tool(
      name: "things_open_search",
      title: "Open Things Search",
      description: "Open the native Things search screen, optionally with a query.",
      systemImage: "magnifyingglass.circle",
      inputSchema: .object(
        properties: [
          "query": .string(description: "Optional native search query.")
        ],
        additionalProperties: false
      ),
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    ) { arguments in
      let query = try ToolArgumentsDecoder(arguments: arguments).optionalString("query")
      let callback = try await self.callbackExecutor.execute(
        try self.urlBuilder.searchURL(query: query, callbacks: nil))
      return ThingsNavigationResult(
        action: "search",
        target: query,
        confirmed: true,
        parameters: callback.parameters,
        message: "Things search screen opened."
      )
    }
  }

  func versionTool() -> Tool {
    Tool(
      name: "things_version",
      title: "Get Things URL Version",
      description: "Return the Things client build and supported URL scheme version.",
      systemImage: "info.circle",
      inputSchema: .object(additionalProperties: false),
      readOnlyHint: true,
      openWorldHint: false
    ) { _ in
      let callback = try await self.callbackExecutor.execute(
        try self.urlBuilder.versionURL(callbacks: nil))
      return ThingsVersionResult(
        schemeVersion: callback.parameters["x-things-scheme-version"]?.first,
        clientVersion: callback.parameters["x-things-client-version"]?.first,
        confirmed: true
      )
    }
  }
}

private struct ThingsNavigationResult: Encodable, Sendable {
  let action: String
  let target: String?
  let confirmed: Bool
  let parameters: [String: [String]]
  let message: String
}

private struct ThingsVersionResult: Encodable, Sendable {
  let schemeVersion: String?
  let clientVersion: String?
  let confirmed: Bool

  enum CodingKeys: String, CodingKey {
    case schemeVersion = "scheme_version"
    case clientVersion = "client_version"
    case confirmed
  }
}
