import Foundation
import JSONSchema
import OrderedCollections

extension ThingsToolService {
  func saveAreaTool() -> Tool {
    Tool(
      name: "things_save_area",
      title: "Save Things Area",
      description:
        "Create or update a Things area through the app's automation interface. Omit id to create. On automation failure, read the area back because multi-property writes may partially apply.",
      systemImage: "square.grid.2x2.fill",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Area ID or area:<id>. Omit when creating."),
          "title": .string(description: "Area title. Required when creating."),
          "tags": nullableStringArraySchema(
            "Replacement area tag names. Empty array or null clears tags."),
          "collapsed": .boolean(description: "Whether the area is collapsed in the sidebar."),
        ],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var request = ThingsAreaAutomationRequest()
      request.id = try decoder.optionalString("id")
      request.title = try decoder.optionalString("title")
      request.tags = try self.patchStringArray("tags", arguments: arguments)
      request.collapsed = try decoder.optionalBool("collapsed")
      if request.isCreate {
        guard request.title != nil else {
          throw ThingsServiceError.missingRequiredArgument("title")
        }
      } else {
        _ = try ThingsEntityID.rawID(request.id ?? "", expectedKind: .area)
        guard request.title != nil || request.tags.isChanged || request.collapsed != nil else {
          throw ThingsServiceError.noChanges
        }
      }
      try await self.validateWriteTags(request.tags, additional: nil)
      return try await self.automationExecutor.execute(.saveArea(request))
    }
  }

  func saveTagTool() -> Tool {
    Tool(
      name: "things_save_tag",
      title: "Save Things Tag",
      description:
        "Create or update a Things tag, including keyboard shortcut and parent tag. Omit id to create. On automation failure, read the tag back because multi-property writes may partially apply.",
      systemImage: "tag.fill",
      inputSchema: .object(
        properties: [
          "id": .string(description: "Tag ID or tag:<id>. Omit when creating."),
          "title": .string(description: "Tag title. Required when creating."),
          "shortcut": nullableStringSchema("Keyboard shortcut. Null clears it."),
          "parent": nullableStringSchema("Parent tag ID or exact title. Null makes it top-level."),
        ],
        additionalProperties: false
      ),
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: false
    ) { arguments in
      let decoder = ToolArgumentsDecoder(arguments: arguments)
      var request = ThingsTagAutomationRequest()
      request.id = try decoder.optionalString("id")
      request.title = try decoder.optionalString("title")
      request.shortcut = try self.patchString("shortcut", arguments: arguments)
      request.parent = try self.patchString("parent", arguments: arguments)
      if request.isCreate {
        guard let title = request.title else {
          throw ThingsServiceError.missingRequiredArgument("title")
        }
        try await self.validateNewTagTitle(title)
      } else {
        _ = try ThingsEntityID.rawID(request.id ?? "", expectedKind: .tag)
        guard request.title != nil || request.shortcut.isChanged || request.parent.isChanged else {
          throw ThingsServiceError.noChanges
        }
      }
      if case .value(let parent) = request.parent {
        let parentRef = try await self.resolveTagReference(parent)
        if let id = request.id,
          ThingsEntityID.parse(id).rawID == ThingsEntityID.parse(parentRef).rawID
        {
          throw ThingsServiceError.invalidValue("parent", reason: "a tag cannot parent itself")
        }
        request.parent = .value(parentRef)
      }
      return try await self.automationExecutor.execute(.saveTag(request))
    }
  }

  private func resolveTagReference(_ value: String) async throws -> String {
    try await activate()
    let parsed = ThingsEntityID.parse(value)
    if parsed.kind != nil || looksLikeThingsID(value) {
      if let kind = parsed.kind, kind != .tag {
        throw ThingsServiceError.entityTypeMismatch(expected: "tag", actual: kind.rawValue)
      }
      let reference = ThingsEntityID.make(.tag, rawID: parsed.rawID)
      _ = try repository.fetch(reference, includeItems: false)
      return reference
    }

    var query = ThingsDirectoryQuery()
    query.query = value
    query.page = ThingsPageRequest(limit: ThingsPageRequest.maximumLimit)
    let matches = try repository.listTags(query).items.filter {
      $0.title.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    guard let match = matches.first else { throw ThingsServiceError.entityNotFound(value) }
    guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(value) }
    return match.id
  }

  private func validateNewTagTitle(_ title: String) async throws {
    try await activate()
    var offset = 0
    repeat {
      var query = ThingsDirectoryQuery()
      query.query = title
      query.page = ThingsPageRequest(offset: offset, limit: ThingsPageRequest.maximumLimit)
      let page = try repository.listTags(query)
      if page.items.contains(where: {
        $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      }) {
        throw ThingsServiceError.invalidValue(
          "title", reason: "a tag with this title already exists; provide its id to update it")
      }
      guard let cursor = page.nextCursor, let nextOffset = Int(cursor) else { return }
      offset = nextOffset
    } while true
  }
}
