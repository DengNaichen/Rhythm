import Foundation

nonisolated extension ThingsURLBuilder {
  func showURL(id: String, filterTags: [String]?) throws -> URL {
    try showURL(id: id, filterTags: filterTags, callbacks: nil)
  }

  func showURL(
    id: String,
    filterTags: [String]?,
    callbacks: ThingsURLCallbacks?
  ) throws -> URL {
    try validateDelimitedValues(filterTags, key: "filter", delimiter: ",")
    var queryItems: [(String, String)] = [("id", ThingsEntityID.parse(id).rawID)]

    if let filterTags, !filterTags.isEmpty {
      queryItems.append(("filter", filterTags.joined(separator: ",")))
    }
    appendCallbacks(callbacks, to: &queryItems)

    return try buildURL(command: "show", queryItems: queryItems)
  }

  func showURL(
    query: String,
    filterTags: [String]? = nil,
    callbacks: ThingsURLCallbacks? = nil
  ) throws -> URL {
    try validateDelimitedValues(filterTags, key: "filter", delimiter: ",")
    var queryItems: [(String, String)] = [("query", query)]
    if let filterTags, !filterTags.isEmpty {
      queryItems.append(("filter", filterTags.joined(separator: ",")))
    }
    appendCallbacks(callbacks, to: &queryItems)
    return try buildURL(command: "show", queryItems: queryItems)
  }

  func searchURL(
    query: String? = nil,
    callbacks: ThingsURLCallbacks? = nil
  ) throws -> URL {
    var queryItems: [(String, String)] = []
    if let query {
      queryItems.append(("query", query))
    }
    appendCallbacks(callbacks, to: &queryItems)
    return try buildURL(command: "search", queryItems: queryItems)
  }

  func versionURL(callbacks: ThingsURLCallbacks? = nil) throws -> URL {
    var queryItems: [(String, String)] = []
    appendCallbacks(callbacks, to: &queryItems)
    return try buildURL(command: "version", queryItems: queryItems)
  }
}
