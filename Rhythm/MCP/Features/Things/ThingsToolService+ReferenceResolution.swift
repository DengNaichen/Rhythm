import Foundation
import OrderedCollections

extension ThingsToolService {
  func normalizedTodoWriteReferences(
    _ request: ThingsTodoSaveRequest,
    arguments: [String: Value]
  ) async throws -> ThingsTodoSaveRequest {
    var normalized = request
    let projectPatch = try patchString("project", arguments: arguments)
    let areaPatch = try patchString("area", arguments: arguments)
    let headingPatch = try patchString("heading", arguments: arguments)

    var project: ThingsProject?
    if case .value(let value) = projectPatch {
      let resolvedProject = try await existingProject(value, argument: "project")
      project = resolvedProject
      normalized.destination = .value(resolvedProject.id)
    }
    if case .value(let value) = areaPatch {
      let area = try await existingArea(value, argument: "area")
      normalized.destination = .value(area.id)
    }

    guard case .value(let value) = headingPatch else { return normalized }
    let heading = try await existingHeading(value, argument: "heading")
    normalized.heading = .value(heading.id)
    let expectedProject: ThingsProject
    if let project {
      expectedProject = project
    } else if let todoID = try ToolArgumentsDecoder(arguments: arguments).optionalString("id") {
      try await activate()
      let todo = try repository.getTodo(id: todoID)
      guard let currentProject = todo.project else {
        throw ThingsServiceError.invalidValue(
          "heading", reason: "the todo is not currently inside a project")
      }
      expectedProject = try await existingProject(currentProject.id, argument: "project")
    } else {
      throw ThingsServiceError.invalidValue(
        "heading", reason: "a project is required when assigning a heading")
    }

    guard
      ThingsEntityID.parse(heading.project.id).rawID
        == ThingsEntityID.parse(expectedProject.id).rawID
    else {
      throw ThingsServiceError.invalidValue(
        "heading", reason: "the heading does not belong to the selected project")
    }
    return normalized
  }

  func normalizedProjectWriteReferences(
    _ request: ThingsProjectSaveRequest,
    arguments: [String: Value]
  ) async throws -> ThingsProjectSaveRequest {
    var normalized = request
    if case .value(let value) = try patchString("area", arguments: arguments) {
      let area = try await existingArea(value, argument: "area")
      normalized.area = .value(area.id)
    }
    return normalized
  }

  func validateJSONReferences(_ items: [ThingsJSONItem]) async throws {
    for (index, item) in items.enumerated() {
      let path = "items[\(index)].attributes"
      switch item {
      case .todo(let operation, let id, let attributes):
        let container: ThingsResolvedContainer?
        if let listID = attributes.listID {
          container = try await existingContainer(id: listID, argument: "\(path).list-id")
        } else if let list = attributes.list {
          container = try await existingContainer(title: list, argument: "\(path).list")
        } else {
          container = nil
        }

        guard let headingValue = attributes.headingID ?? attributes.heading else { continue }
        let heading = try await existingHeading(headingValue, argument: "\(path).heading")
        let projectID: String
        if let container {
          guard container.kind == .project else {
            throw ThingsServiceError.invalidValue(
              "\(path).heading", reason: "a heading requires a project destination")
          }
          projectID = container.rawID
        } else if operation == .update, let id {
          try await activate()
          let todo = try repository.getTodo(id: id)
          guard let project = todo.project else {
            throw ThingsServiceError.invalidValue(
              "\(path).heading", reason: "the todo is not currently inside a project")
          }
          projectID = ThingsEntityID.parse(project.id).rawID
        } else {
          throw ThingsServiceError.invalidValue(
            "\(path).heading", reason: "a project destination is required")
        }
        guard ThingsEntityID.parse(heading.project.id).rawID == projectID else {
          throw ThingsServiceError.invalidValue(
            "\(path).heading", reason: "the heading does not belong to the selected project")
        }

      case .project(_, _, let attributes):
        if let areaID = attributes.areaID {
          _ = try await existingArea(areaID, argument: "\(path).area-id")
        } else if let area = attributes.area {
          _ = try await existingArea(area, argument: "\(path).area")
        }
      }
    }
  }

  private func existingProject(_ value: String, argument: String) async throws -> ThingsProject {
    try await activate()
    let parsed = ThingsEntityID.parse(value)
    if let kind = parsed.kind, kind != .project {
      throw ThingsServiceError.invalidValue(argument, reason: "expected a project ID or title")
    }
    return try repository.getProject(idOrTitle: value, includeTodos: false)
  }

  private func existingHeading(_ value: String, argument: String) async throws -> ThingsHeading {
    try await activate()
    let parsed = ThingsEntityID.parse(value)
    if let kind = parsed.kind, kind != .heading {
      throw ThingsServiceError.invalidValue(argument, reason: "expected a heading ID or title")
    }
    return try repository.getHeading(idOrTitle: value, includeTodos: false)
  }

  private func existingArea(_ value: String, argument: String) async throws -> ThingsArea {
    try await activate()
    let parsed = ThingsEntityID.parse(value)
    if let kind = parsed.kind, kind != .area {
      throw ThingsServiceError.invalidValue(argument, reason: "expected an area ID or title")
    }
    if parsed.kind == .area || looksLikeThingsID(parsed.rawID) {
      let reference = ThingsEntityID.make(.area, rawID: parsed.rawID)
      let entity = try repository.fetch(reference, includeItems: false)
      guard case .area(let area) = entity else {
        throw ThingsServiceError.invalidValue(argument, reason: "expected an area reference")
      }
      return area
    }

    var query = ThingsDirectoryQuery()
    query.query = value
    query.page = ThingsPageRequest(limit: ThingsPageRequest.maximumLimit)
    let matches = try repository.listAreas(query).items.filter {
      $0.title.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    guard let match = matches.first else { throw ThingsServiceError.entityNotFound(value) }
    guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(value) }
    return match
  }

  private func existingContainer(id value: String, argument: String) async throws
    -> ThingsResolvedContainer
  {
    try await activate()
    let parsed = ThingsEntityID.parse(value)
    switch parsed.kind {
    case .project:
      let project = try await existingProject(value, argument: argument)
      return ThingsResolvedContainer(kind: .project, rawID: ThingsEntityID.parse(project.id).rawID)
    case .area:
      let area = try await existingArea(value, argument: argument)
      return ThingsResolvedContainer(kind: .area, rawID: ThingsEntityID.parse(area.id).rawID)
    case .todo, .heading, .tag, .all:
      throw ThingsServiceError.invalidValue(argument, reason: "expected a project or area ID")
    case nil:
      let entity = try repository.fetch(parsed.rawID, includeItems: false)
      switch entity {
      case .project(let project):
        return ThingsResolvedContainer(
          kind: .project, rawID: ThingsEntityID.parse(project.id).rawID)
      case .area(let area):
        return ThingsResolvedContainer(kind: .area, rawID: ThingsEntityID.parse(area.id).rawID)
      case .todo, .heading, .tag:
        throw ThingsServiceError.invalidValue(argument, reason: "expected a project or area ID")
      }
    }
  }

  private func existingContainer(title value: String, argument: String) async throws
    -> ThingsResolvedContainer
  {
    try await activate()
    var matches: [ThingsResolvedContainer] = []
    do {
      let project = try repository.getProject(idOrTitle: value, includeTodos: false)
      matches.append(
        ThingsResolvedContainer(kind: .project, rawID: ThingsEntityID.parse(project.id).rawID))
    } catch ThingsServiceError.entityNotFound {
      // Continue looking for an area with the same exact title.
    }

    do {
      let area = try await existingArea(value, argument: argument)
      matches.append(
        ThingsResolvedContainer(kind: .area, rawID: ThingsEntityID.parse(area.id).rawID))
    } catch ThingsServiceError.entityNotFound {
      // No matching area.
    }

    guard let match = matches.first else { throw ThingsServiceError.entityNotFound(value) }
    guard matches.count == 1 else { throw ThingsServiceError.ambiguousReference(value) }
    return match
  }

  func looksLikeThingsID(_ value: String) -> Bool {
    let raw = ThingsEntityID.parse(value).rawID
    guard raw.count >= 20 else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return raw.unicodeScalars.allSatisfy(allowed.contains)
  }
}

private struct ThingsResolvedContainer: Sendable {
  let kind: ThingsEntityKind
  let rawID: String
}
