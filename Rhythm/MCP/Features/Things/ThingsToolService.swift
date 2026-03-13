import AppKit
import Foundation
import JSONSchema
import OrderedCollections

private let thingsGroupContainerPath =
    "/Users/\(NSUserName())/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac"
private let thingsDatabaseBookmarkKey = "things.databaseBookmark"

@MainActor
final class ThingsToolService: Service, ThingsDatabaseAccessing {
    let id = "things"
    let displayName = "Things"

    private let urlBuilder: ThingsURLBuilding
    private let urlExecutor: ThingsURLExecuting
    private lazy var store = ThingsStore(databaseAccess: self)

    init(
        urlBuilder: ThingsURLBuilding = ThingsURLBuilder(),
        urlExecutor: ThingsURLExecuting = WorkspaceThingsURLExecutor()
    ) {
        self.urlBuilder = urlBuilder
        self.urlExecutor = urlExecutor
    }

    func tools() -> [Tool] {
        [
            Tool(
                name: "add_todo",
                title: "Add Todo",
                description: "Create a new todo in Things.",
                systemImage: "plus.square.on.square",
                inputSchema: .object(
                    properties: [
                        "title": .string(description: "Title of the todo"),
                        "notes": .string(description: "Optional notes for the todo"),
                        "when": .string(
                            description: "Schedule value such as today, tomorrow, or YYYY-MM-DD"
                        ),
                        "deadline": .string(description: "Deadline in YYYY-MM-DD format"),
                        "tags": .array(
                            description: "Tags to apply to the todo",
                            items: .string()
                        ),
                        "checklist_items": .array(
                            description: "Checklist items to add to the todo",
                            items: .string()
                        ),
                        "list_id": .string(description: "Destination project or area identifier"),
                        "list_title": .string(description: "Destination project or area title"),
                        "heading": .string(description: "Heading title to place the todo under"),
                        "heading_id": .string(description: "Heading identifier to place the todo under"),
                    ],
                    required: ["title"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            ) { arguments in
                let request = try self.taskCreationRequest(from: arguments)
                let normalized = try request.normalized()
                let url = try self.urlBuilder.addTodoURL(for: normalized)
                try self.urlExecutor.execute(url)
                return ThingsActionResult(
                    message: self.successMessage(for: normalized),
                    id: nil,
                    title: normalized.title
                )
            },
            Tool(
                name: "get_today",
                title: "Get Today",
                description: "Get todos due today from Things.",
                systemImage: "sun.max",
                inputSchema: .object(properties: [:], additionalProperties: false),
                readOnlyHint: true,
                openWorldHint: false
            ) { _ in
                try await self.activate()
                return ThingsCollectionResponse(items: try self.store.getTodayTodos())
            },
            Tool(
                name: "get_inbox",
                title: "Get Inbox",
                description: "Get todos from Inbox in Things.",
                systemImage: "tray",
                inputSchema: .object(properties: [:], additionalProperties: false),
                readOnlyHint: true,
                openWorldHint: false
            ) { _ in
                try await self.activate()
                return ThingsCollectionResponse(items: try self.store.getInboxTodos())
            },
            Tool(
                name: "get_todos_for_date",
                title: "Get Todos For Date",
                description: "Get scheduled todos for a specific date in Things.",
                systemImage: "calendar",
                inputSchema: .object(
                    properties: [
                        "date": .string(description: "Date in YYYY-MM-DD format")
                    ],
                    required: ["date"],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await self.activate()
                let date = try self.requiredString("date", in: arguments)
                return ThingsCollectionResponse(items: try self.store.getScheduledTodos(on: date))
            },
            Tool(
                name: "get_projects",
                title: "Get Projects",
                description: "Get projects from Things.",
                systemImage: "folder",
                inputSchema: .object(
                    properties: [
                        "include_items": .boolean(description: "Include tasks within projects")
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await self.activate()
                let includeItems = try self.optionalBool("include_items", in: arguments) ?? false
                return ThingsCollectionResponse(
                    items: try self.store.getProjects(includeItems: includeItems)
                )
            },
            Tool(
                name: "get_areas",
                title: "Get Areas",
                description: "Get areas from Things.",
                systemImage: "square.grid.2x2",
                inputSchema: .object(
                    properties: [
                        "include_items": .boolean(
                            description: "Include projects and tasks within areas"
                        )
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await self.activate()
                let includeItems = try self.optionalBool("include_items", in: arguments) ?? false
                return ThingsCollectionResponse(
                    items: try self.store.getAreas(includeItems: includeItems)
                )
            },
            Tool(
                name: "get_tags",
                title: "Get Tags",
                description: "Get tags from Things.",
                systemImage: "tag",
                inputSchema: .object(
                    properties: [
                        "include_items": .boolean(
                            description: "Include items tagged with each tag"
                        )
                    ],
                    additionalProperties: false
                ),
                readOnlyHint: true,
                openWorldHint: false
            ) { arguments in
                try await self.activate()
                let includeItems = try self.optionalBool("include_items", in: arguments) ?? false
                return ThingsCollectionResponse(
                    items: try self.store.getTags(includeItems: includeItems)
                )
            },
            Tool(
                name: "show_item",
                title: "Show Item",
                description: "Show a specific item or list in Things.",
                systemImage: "arrow.up.forward.square",
                inputSchema: .object(
                    properties: [
                        "target": .string(description: "List keyword, UUID, or exact title"),
                        "query": .string(description: "Optional list query filter"),
                        "filter_tags": .array(
                            description: "Optional list tag filters",
                            items: .string()
                        ),
                    ],
                    required: ["target"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            ) { arguments in
                let request = ShowItemRequest(
                    target: try self.requiredString("target", in: arguments),
                    query: try self.optionalString("query", in: arguments),
                    filterTags: try self.optionalStringArray("filter_tags", in: arguments)
                )
                return try await self.showItem(request: request)
            },
            Tool(
                name: "complete_todo",
                title: "Complete Todo",
                description: "Mark a todo as completed in Things.",
                systemImage: "checkmark.circle",
                inputSchema: .object(
                    properties: [
                        "target": .string(description: "Todo UUID or exact title")
                    ],
                    required: ["target"],
                    additionalProperties: false
                ),
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            ) { arguments in
                try await self.activate()
                let target = try self.requiredString("target", in: arguments)
                let resolvedTodo = try self.store.resolveCompletableTodo(target)
                guard let authToken = try self.store.authToken(), !authToken.isEmpty else {
                    throw ThingsToolServiceError.missingAuthToken
                }

                let url = try self.urlBuilder.completeTodoURL(
                    id: resolvedTodo.id,
                    authToken: authToken
                )
                try self.urlExecutor.execute(url)
                return ThingsActionResult(
                    message: "Completed todo: \(resolvedTodo.title)",
                    id: resolvedTodo.id,
                    title: resolvedTodo.title
                )
            },
        ]
    }

    func isActivated() async -> Bool {
        canAccessDatabaseAtDefaultPath || canAccessDatabaseUsingBookmark
    }

    func activate() async throws {
        guard canAccessDatabaseAtDefaultPath || canAccessDatabaseUsingBookmark else {
            throw ThingsToolServiceError.databaseAccessRequired
        }
    }

    func withReadableDatabaseURL<T>(_ operation: (URL) throws -> T) throws -> T {
        if let defaultURL = defaultDatabaseURL(),
            FileManager.default.isReadableFile(atPath: defaultURL.path)
        {
            return try operation(defaultURL)
        }

        let rootURL = try resolveBookmarkURL()
        return try withSecurityScopedAccess(rootURL) { url in
            let databaseURL = try self.resolveDatabaseURL(from: url)
            guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
                throw ThingsToolServiceError.databaseAccessRequired
            }
            return try operation(databaseURL)
        }
    }

    private var canAccessDatabaseAtDefaultPath: Bool {
        guard let defaultURL = defaultDatabaseURL() else {
            return false
        }
        return FileManager.default.isReadableFile(atPath: defaultURL.path)
    }

    private var canAccessDatabaseUsingBookmark: Bool {
        do {
            let rootURL = try resolveBookmarkURL()
            return try withSecurityScopedAccess(rootURL) { url in
                let databaseURL = try self.resolveDatabaseURL(from: url)
                return FileManager.default.isReadableFile(atPath: databaseURL.path)
            }
        } catch {
            return false
        }
    }

    private func defaultDatabaseURL() -> URL? {
        let baseDirectory = URL(fileURLWithPath: thingsGroupContainerPath)
        return try? resolveDatabaseURL(from: baseDirectory)
    }

    private func directShowTarget(for target: String) -> ShowTarget? {
        let normalized = normalizeScalar(target) ?? target
        let lowercased = normalized.lowercased()
        if ["inbox", "today", "upcoming", "anytime", "someday", "logbook", "trash"].contains(lowercased) {
            return .list(id: lowercased)
        }

        if looksLikeUUID(normalized) {
            return .item(id: normalized, displayTitle: normalized)
        }

        return nil
    }

    private func looksLikeUUID(_ value: String) -> Bool {
        guard value.count >= 20 else {
            return false
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func taskCreationRequest(from arguments: [String: Value]) throws -> ThingsTaskCreationRequest {
        ThingsTaskCreationRequest(
            title: try requiredString("title", in: arguments),
            notes: try optionalString("notes", in: arguments),
            when: try optionalString("when", in: arguments),
            deadline: try optionalString("deadline", in: arguments),
            tags: try optionalStringArray("tags", in: arguments),
            checklistItems: try optionalStringArray("checklist_items", in: arguments),
            listID: try optionalString("list_id", in: arguments),
            listTitle: try optionalString("list_title", in: arguments),
            heading: try optionalString("heading", in: arguments),
            headingID: try optionalString("heading_id", in: arguments)
        )
    }

    private func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
        guard let value = arguments[key] else {
            throw ThingsToolServiceError.missingRequiredArgument(key)
        }

        guard let stringValue = value.stringValue else {
            throw ThingsToolServiceError.invalidType(key, expected: "string")
        }

        return stringValue
    }

    private func optionalString(_ key: String, in arguments: [String: Value]) throws -> String? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let stringValue = value.stringValue else {
            throw ThingsToolServiceError.invalidType(key, expected: "string")
        }

        return stringValue
    }

    private func optionalStringArray(_ key: String, in arguments: [String: Value]) throws -> [String]? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let arrayValue = value.arrayValue else {
            throw ThingsToolServiceError.invalidType(key, expected: "array of strings")
        }

        return try arrayValue.map { element in
            guard let stringValue = element.stringValue else {
                throw ThingsToolServiceError.invalidType(key, expected: "array of strings")
            }
            return stringValue
        }
    }

    private func optionalBool(_ key: String, in arguments: [String: Value]) throws -> Bool? {
        guard let value = arguments[key] else {
            return nil
        }

        guard let boolValue = value.boolValue else {
            throw ThingsToolServiceError.invalidType(key, expected: "boolean")
        }

        return boolValue
    }

    private func normalizeScalar(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeTags(_ values: [String]?) -> [String]? {
        guard let values else {
            return nil
        }

        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return normalized.isEmpty ? nil : normalized
    }

    private func showItem(request: ShowItemRequest) async throws -> ThingsActionResult {
        let target = normalizeScalar(request.target) ?? request.target
        let query = normalizeScalar(request.query)
        let filterTags = normalizeTags(request.filterTags)

        if let directTarget = directShowTarget(for: target) {
            switch directTarget {
            case let .list(id):
                let url = try urlBuilder.showURL(id: id, query: query, filterTags: filterTags)
                try urlExecutor.execute(url)
                return ThingsActionResult(message: "Showing item: \(id)", id: id, title: id)
            case let .item(id, displayTitle):
                guard query == nil, filterTags == nil else {
                    throw ThingsToolServiceError.listFiltersRequireListTarget
                }
                let url = try urlBuilder.showURL(id: id, query: nil, filterTags: nil)
                try urlExecutor.execute(url)
                return ThingsActionResult(
                    message: "Showing item: \(displayTitle)",
                    id: id,
                    title: displayTitle
                )
            }
        }

        try await activate()
        let resolvedTarget = try store.resolveShowTarget(target)
        switch resolvedTarget {
        case let .list(id):
            let url = try urlBuilder.showURL(id: id, query: query, filterTags: filterTags)
            try urlExecutor.execute(url)
            return ThingsActionResult(message: "Showing item: \(id)", id: id, title: id)
        case let .item(id, displayTitle):
            guard query == nil, filterTags == nil else {
                throw ThingsToolServiceError.listFiltersRequireListTarget
            }
            let url = try urlBuilder.showURL(id: id, query: nil, filterTags: nil)
            try urlExecutor.execute(url)
            return ThingsActionResult(message: "Showing item: \(displayTitle)", id: id, title: displayTitle)
        }
    }

    private func successMessage(for request: NormalizedThingsTaskCreationRequest) -> String {
        var detailParts: [String] = []

        if let when = request.when {
            detailParts.append("when=\(when)")
        }

        if !request.tags.isEmpty {
            detailParts.append("tags=\(request.tags.joined(separator: ","))")
        }

        if request.listID != nil || request.listTitle != nil || request.headingID != nil || request.heading != nil {
            detailParts.append("destination=custom")
        }

        if detailParts.isEmpty {
            return "Created new todo: \(request.title)"
        }

        return "Created new todo: \(request.title) (\(detailParts.joined(separator: "; ")))"
    }

    private func withSecurityScopedAccess<T>(_ url: URL, _ operation: (URL) throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw ThingsToolServiceError.databaseAccessRequired
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try operation(url)
    }

    private func resolveBookmarkURL() throws -> URL {
        guard let bookmarkData = UserDefaults.standard.data(forKey: thingsDatabaseBookmarkKey) else {
            throw ThingsToolServiceError.databaseAccessRequired
        }

        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func resolveDatabaseURL(from selectionURL: URL) throws -> URL {
        if selectionURL.lastPathComponent == "main.sqlite" {
            return selectionURL
        }

        if selectionURL.pathExtension == "thingsdatabase"
            || selectionURL.lastPathComponent == "Things Database.thingsdatabase"
        {
            return selectionURL.appendingPathComponent("main.sqlite")
        }

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(
            at: selectionURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "main.sqlite",
                    url.path.contains("Things Database.thingsdatabase")
                {
                    return url
                }
            }
        }

        throw ThingsToolServiceError.databaseAccessRequired
    }
}

enum ThingsToolServiceError: Error, LocalizedError {
    case databaseAccessRequired
    case listFiltersRequireListTarget
    case missingAuthToken
    case missingRequiredArgument(String)
    case invalidType(String, expected: String)

    var errorDescription: String? {
        switch self {
        case .databaseAccessRequired:
            return "Things database access is required."
        case .listFiltersRequireListTarget:
            return "query and filter_tags can only be used with list targets"
        case .missingAuthToken:
            return "Could not read the Things URL auth token."
        case let .missingRequiredArgument(argument):
            return "Missing required argument: \(argument)"
        case let .invalidType(argument, expected):
            return "Invalid argument type for \(argument): expected \(expected)"
        }
    }
}
