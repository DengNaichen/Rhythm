//
//  ThingsStore.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//


import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

protocol ThingsDatabaseAccessing: AnyObject {
    func withReadableDatabaseURL<T>(_ operation: (URL) throws -> T) throws -> T
}

enum ThingsDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Failed to open Things database: \(message)"
        case let .prepareFailed(message):
            return "Failed to prepare Things database query: \(message)"
        case let .stepFailed(message):
            return "Failed to read from Things database: \(message)"
        }
    }
}

final class ThingsStore {
    private let databaseAccess: any ThingsDatabaseAccessing
    private let listKeywords: Set<String> = [
        "inbox", "today", "upcoming", "anytime", "someday", "logbook", "trash",
    ]

    init(databaseAccess: any ThingsDatabaseAccessing) {
        self.databaseAccess = databaseAccess
    }

    func getTodayTodos() throws -> [ThingsTodo] {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                let todayThreshold = Self.thingsDate(for: Date())
                let regularTodayTodos = try fetchTodos(
                    in: database,
                    predicate: "TASK.start = 1 AND TASK.startDate IS NOT NULL"
                )
                let unconfirmedScheduledTodos = try fetchTodos(
                    in: database,
                    predicate: "TASK.start = 2 AND TASK.startDate <= \(todayThreshold)"
                )
                let overdueTodos = try fetchTodos(
                    in: database,
                    predicate: """
                    TASK.startDate IS NULL
                    AND TASK.deadline <= \(todayThreshold)
                    AND TASK.deadlineSuppressionDate IS NULL
                    """
                )

                return (regularTodayTodos + unconfirmedScheduledTodos + overdueTodos)
                    .filter { $0.parentProjectStart != "Someday" }
                    .sorted { lhs, rhs in
                        if lhs.todayIndex != rhs.todayIndex {
                            return lhs.todayIndex < rhs.todayIndex
                        }
                        return (lhs.startDate ?? "") < (rhs.startDate ?? "")
                    }
            }
        }
    }

    func getInboxTodos() throws -> [ThingsTodo] {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                try fetchTodos(
                    in: database,
                    predicate: "TASK.start = 0",
                    orderBy: "TASK.\"index\""
                )
            }
        }
    }

    func getScheduledTodos(on date: String) throws -> [ThingsTodo] {
        let threshold = try Self.thingsDate(forISODate: date)

        return try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                try fetchTodos(
                    in: database,
                    predicate: "TASK.startDate = \(threshold)",
                    orderBy: "TASK.startDate, TASK.\"index\""
                )
            }
        }
    }

    func resolveShowTarget(_ target: String) throws -> ShowTarget {
        let normalizedTarget = normalizeTarget(target)
        if listKeywords.contains(normalizedTarget.lowercased()) {
            return .list(id: normalizedTarget.lowercased())
        }

        return try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                if let match = try fetchShowableByUUID(normalizedTarget, in: database) {
                    return .item(id: match.id, displayTitle: match.title)
                }

                let matches = try fetchShowableByTitle(normalizedTarget, in: database)
                if matches.isEmpty {
                    throw ThingsResolutionError.showTargetNotFound(normalizedTarget)
                }

                if matches.count > 1 {
                    throw ThingsResolutionError.ambiguousShowTarget(normalizedTarget)
                }

                let match = matches[0]
                return .item(id: match.id, displayTitle: match.title)
            }
        }
    }

    func resolveCompletableTodo(_ target: String) throws -> CompletableTodoReference {
        let normalizedTarget = normalizeTarget(target)

        return try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                if let uuidMatch = try fetchTodoStatusByUUID(normalizedTarget, in: database) {
                    return try validateCompletableMatch(uuidMatch, originalTarget: normalizedTarget)
                }

                let matches = try fetchTodoStatusesByTitle(normalizedTarget, in: database)
                let incompleteMatches = matches.filter { $0.status == .incomplete }

                if incompleteMatches.count > 1 {
                    throw ThingsResolutionError.ambiguousCompletableTodo(normalizedTarget)
                }

                if let incompleteMatch = incompleteMatches.first {
                    return incompleteMatch
                }

                if matches.count == 1, let onlyMatch = matches.first {
                    return try validateCompletableMatch(onlyMatch, originalTarget: normalizedTarget)
                }

                if matches.count > 1 {
                    throw ThingsResolutionError.ambiguousCompletableTodo(normalizedTarget)
                }

                throw ThingsResolutionError.completableTodoNotFound(normalizedTarget)
            }
        }
    }

    func authToken() throws -> String? {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                let statement = try prepareStatement(
                    in: database,
                    sql: """
                    SELECT uriSchemeAuthenticationToken
                    FROM TMSettings
                    WHERE uuid = 'RhAzEf6qDxCD5PmnZVtBZR'
                    """
                )
                defer { sqlite3_finalize(statement) }

                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    return Self.stringValue(statement, column: 0)
                }

                if result == SQLITE_DONE {
                    return nil
                }

                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }
    }

    func getProjects(includeItems: Bool) throws -> [ThingsProject] {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                let statement = try prepareStatement(
                    in: database,
                    sql: """
                    SELECT
                        PROJECT.uuid,
                        PROJECT.title,
                        AREA.title AS area_title,
                        PROJECT.notes,
                        datetime(PROJECT.creationDate, 'unixepoch', 'localtime') AS created,
                        datetime(PROJECT.userModificationDate, 'unixepoch', 'localtime') AS modified
                    FROM TMTask AS PROJECT
                    LEFT OUTER JOIN TMArea AS AREA ON PROJECT.area = AREA.uuid
                    WHERE PROJECT.type = 1
                      AND PROJECT.status = 0
                      AND PROJECT.trashed = 0
                    ORDER BY PROJECT."index"
                    """
                )
                defer { sqlite3_finalize(statement) }

                var projects: [ThingsProject] = []
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_ROW {
                        let uuid = Self.stringValue(statement, column: 0) ?? ""
                        projects.append(
                            ThingsProject(
                                uuid: uuid,
                                title: Self.stringValue(statement, column: 1) ?? "",
                                areaTitle: Self.stringValue(statement, column: 2),
                                notes: Self.stringValue(statement, column: 3),
                                created: Self.stringValue(statement, column: 4),
                                modified: Self.stringValue(statement, column: 5),
                                headingTitles: try fetchHeadingTitles(forProject: uuid, in: database),
                                todoTitles: includeItems ? try fetchTodoTitles(forProject: uuid, in: database) : []
                            )
                        )
                    } else if result == SQLITE_DONE {
                        break
                    } else {
                        throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
                    }
                }

                return projects
            }
        }
    }

    func getAreas(includeItems: Bool) throws -> [ThingsArea] {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                let statement = try prepareStatement(
                    in: database,
                    sql: """
                    SELECT uuid, title
                    FROM TMArea
                    WHERE IFNULL(visible, 1) != 0
                    ORDER BY "index"
                    """
                )
                defer { sqlite3_finalize(statement) }

                var areas: [ThingsArea] = []
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_ROW {
                        let uuid = Self.stringValue(statement, column: 0) ?? ""
                        areas.append(
                            ThingsArea(
                                uuid: uuid,
                                title: Self.stringValue(statement, column: 1) ?? "",
                                projectTitles: includeItems ? try fetchProjectTitles(forArea: uuid, in: database) : [],
                                todoTitles: includeItems ? try fetchTodoTitles(forArea: uuid, in: database) : []
                            )
                        )
                    } else if result == SQLITE_DONE {
                        break
                    } else {
                        throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
                    }
                }

                return areas
            }
        }
    }

    func getTags(includeItems: Bool) throws -> [ThingsTag] {
        try databaseAccess.withReadableDatabaseURL { databaseURL in
            try withDatabase(at: databaseURL.path) { database in
                let statement = try prepareStatement(
                    in: database,
                    sql: """
                    SELECT uuid, title, shortcut
                    FROM TMTag
                    WHERE IFNULL(trashed, 0) = 0
                    ORDER BY "index"
                    """
                )
                defer { sqlite3_finalize(statement) }

                var tags: [ThingsTag] = []
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_ROW {
                        let uuid = Self.stringValue(statement, column: 0) ?? ""
                        tags.append(
                            ThingsTag(
                                uuid: uuid,
                                title: Self.stringValue(statement, column: 1) ?? "",
                                shortcut: Self.stringValue(statement, column: 2),
                                taggedTodoTitles: includeItems ? try fetchTaggedTodoTitles(forTag: uuid, in: database) : []
                            )
                        )
                    } else if result == SQLITE_DONE {
                        break
                    } else {
                        throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
                    }
                }

                return tags
            }
        }
    }

    private func fetchTodos(
        in database: OpaquePointer,
        predicate: String,
        orderBy: String = "TASK.todayIndex"
    ) throws -> [ThingsTodo] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT
                TASK.uuid,
                TASK.title,
                'to-do' AS type,
                CASE
                    WHEN TASK.status = 0 THEN 'incomplete'
                    WHEN TASK.status = 2 THEN 'canceled'
                    WHEN TASK.status = 3 THEN 'completed'
                END AS status,
                CASE
                    WHEN TASK.start = 0 THEN 'Inbox'
                    WHEN TASK.start = 1 THEN 'Anytime'
                    WHEN TASK.start = 2 THEN 'Someday'
                END AS list,
                date(\(Self.thingsDateToISODateExpression(column: "TASK.startDate"))) AS start_date,
                date(\(Self.thingsDateToISODateExpression(column: "TASK.deadline"))) AS deadline,
                datetime(TASK.stopDate, 'unixepoch', 'localtime') AS completed_date,
                datetime(TASK.creationDate, 'unixepoch', 'localtime') AS created,
                datetime(TASK.userModificationDate, 'unixepoch', 'localtime') AS modified,
                AREA.title AS area_title,
                CASE
                    WHEN PROJECT.title IS NOT NULL THEN PROJECT.title
                    WHEN PROJECT_OF_HEADING.title IS NOT NULL THEN PROJECT_OF_HEADING.title
                END AS project_title,
                HEADING.title AS heading_title,
                TASK.notes,
                CASE
                    WHEN PROJECT.start = 0 THEN 'Inbox'
                    WHEN PROJECT.start = 1 THEN 'Anytime'
                    WHEN PROJECT.start = 2 THEN 'Someday'
                    WHEN PROJECT_OF_HEADING.start = 0 THEN 'Inbox'
                    WHEN PROJECT_OF_HEADING.start = 1 THEN 'Anytime'
                    WHEN PROJECT_OF_HEADING.start = 2 THEN 'Someday'
                END AS parent_project_start,
                IFNULL(TASK.todayIndex, 0) AS today_index
            FROM TMTask AS TASK
            LEFT OUTER JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
            LEFT OUTER JOIN TMArea AS AREA ON TASK.area = AREA.uuid
            LEFT OUTER JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
            LEFT OUTER JOIN TMTask AS PROJECT_OF_HEADING ON HEADING.project = PROJECT_OF_HEADING.uuid
            WHERE
                TASK.rt1_recurrenceRule IS NULL
                AND TASK.trashed = 0
                AND NOT IFNULL(PROJECT.trashed, 0)
                AND NOT IFNULL(PROJECT_OF_HEADING.trashed, 0)
                AND TASK.type = 0
                AND TASK.status = 0
                AND \(predicate)
            ORDER BY \(orderBy)
            """
        )
        defer { sqlite3_finalize(statement) }

        var todos: [ThingsTodo] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let uuid = Self.stringValue(statement, column: 0) ?? ""
                let todo = ThingsTodo(
                    uuid: uuid,
                    title: Self.stringValue(statement, column: 1) ?? "",
                    type: Self.stringValue(statement, column: 2) ?? "to-do",
                    status: Self.stringValue(statement, column: 3),
                    list: Self.stringValue(statement, column: 4),
                    startDate: Self.stringValue(statement, column: 5),
                    deadline: Self.stringValue(statement, column: 6),
                    completedDate: Self.stringValue(statement, column: 7),
                    created: Self.stringValue(statement, column: 8),
                    modified: Self.stringValue(statement, column: 9),
                    notes: Self.stringValue(statement, column: 13),
                    areaTitle: Self.stringValue(statement, column: 10),
                    projectTitle: Self.stringValue(statement, column: 11),
                    headingTitle: Self.stringValue(statement, column: 12),
                    parentProjectStart: Self.stringValue(statement, column: 14),
                    tags: try fetchTags(for: uuid, in: database),
                    checklistItems: try fetchChecklistItems(for: uuid, in: database),
                    todayIndex: Int(sqlite3_column_int(statement, 15))
                )
                todos.append(todo)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return todos
    }

    private func fetchShowableByUUID(
        _ uuid: String,
        in database: OpaquePointer
    ) throws -> (id: String, title: String)? {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT uuid, title
            FROM TMTask
            WHERE uuid = ?
              AND type IN (0, 1, 2)
              AND trashed = 0
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uuid, -1, sqliteTransient)

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return (
                Self.stringValue(statement, column: 0) ?? uuid,
                Self.stringValue(statement, column: 1) ?? uuid
            )
        }

        if result == SQLITE_DONE {
            return nil
        }

        throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
    }

    private func fetchShowableByTitle(
        _ title: String,
        in database: OpaquePointer
    ) throws -> [(id: String, title: String)] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT uuid, title
            FROM TMTask
              AND type IN (0, 1, 2)
              AND title = ? COLLATE NOCASE
              AND trashed = 0
            ORDER BY type, uuid
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, title, -1, sqliteTransient)

        var results: [(id: String, title: String)] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                results.append(
                    (
                        id: Self.stringValue(statement, column: 0) ?? "",
                        title: Self.stringValue(statement, column: 1) ?? title
                    )
                )
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return results
    }

    private func fetchTodoStatusByUUID(
        _ uuid: String,
        in database: OpaquePointer
    ) throws -> CompletableTodoReference? {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT uuid, title, status
            FROM TMTask
            WHERE uuid = ?
              AND type = 0
              AND trashed = 0
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uuid, -1, sqliteTransient)

        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return CompletableTodoReference(
                id: Self.stringValue(statement, column: 0) ?? uuid,
                title: Self.stringValue(statement, column: 1) ?? uuid,
                status: Self.todoStatus(from: sqlite3_column_int(statement, 2))
            )
        }

        if result == SQLITE_DONE {
            return nil
        }

        throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
    }

    private func fetchTodoStatusesByTitle(
        _ title: String,
        in database: OpaquePointer
    ) throws -> [CompletableTodoReference] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT uuid, title, status
            FROM TMTask
            WHERE title = ? COLLATE NOCASE
              AND type = 0
              AND trashed = 0
            ORDER BY status, uuid
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, title, -1, sqliteTransient)

        var results: [CompletableTodoReference] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                results.append(
                    CompletableTodoReference(
                        id: Self.stringValue(statement, column: 0) ?? "",
                        title: Self.stringValue(statement, column: 1) ?? title,
                        status: Self.todoStatus(from: sqlite3_column_int(statement, 2))
                    )
                )
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return results
    }

    private func validateCompletableMatch(
        _ match: CompletableTodoReference,
        originalTarget: String
    ) throws -> CompletableTodoReference {
        switch match.status {
        case .incomplete:
            return match
        case .completed:
            throw ThingsResolutionError.todoAlreadyCompleted(
                match.title.isEmpty ? originalTarget : match.title
            )
        case .canceled:
            throw ThingsResolutionError.todoCanceled(
                match.title.isEmpty ? originalTarget : match.title
            )
        }
    }

    private func fetchTags(
        for uuid: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT TAG.title
            FROM TMTaskTag AS TASK_TAG
            LEFT OUTER JOIN TMTag AS TAG ON TAG.uuid = TASK_TAG.tags
            WHERE TASK_TAG.tasks = ?
            ORDER BY TAG."index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uuid, -1, sqliteTransient)

        var tags: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                if let tag = Self.stringValue(statement, column: 0) {
                    tags.append(tag)
                }
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return tags
    }

    private func fetchHeadingTitles(
        forProject projectUUID: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT title
            FROM TMTask
            WHERE type = 2
              AND status = 0
              AND trashed = 0
              AND project = ?
            ORDER BY "index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, projectUUID, -1, sqliteTransient)

        return try fetchSingleStringColumn(from: statement, in: database)
    }

    private func fetchTodoTitles(
        forProject projectUUID: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT TASK.title
            FROM TMTask AS TASK
            LEFT OUTER JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
            WHERE TASK.type = 0
              AND TASK.status = 0
              AND TASK.trashed = 0
              AND TASK.rt1_recurrenceRule IS NULL
              AND NOT IFNULL(HEADING.trashed, 0)
              AND (
                TASK.project = ?
                OR HEADING.project = ?
              )
            ORDER BY TASK."index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, projectUUID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, projectUUID, -1, sqliteTransient)

        return try fetchSingleStringColumn(from: statement, in: database)
    }

    private func fetchProjectTitles(
        forArea areaUUID: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT title
            FROM TMTask
            WHERE type = 1
              AND status = 0
              AND trashed = 0
              AND area = ?
            ORDER BY "index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, areaUUID, -1, sqliteTransient)

        return try fetchSingleStringColumn(from: statement, in: database)
    }

    private func fetchTodoTitles(
        forArea areaUUID: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT TASK.uuid, TASK.title
            FROM TMTask AS TASK
            LEFT OUTER JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
            LEFT OUTER JOIN TMTask AS HEADING ON TASK.heading = HEADING.uuid
            LEFT OUTER JOIN TMTask AS PROJECT_OF_HEADING ON HEADING.project = PROJECT_OF_HEADING.uuid
            WHERE TASK.type = 0
              AND TASK.status = 0
              AND TASK.trashed = 0
              AND TASK.rt1_recurrenceRule IS NULL
              AND NOT IFNULL(PROJECT.trashed, 0)
              AND NOT IFNULL(PROJECT_OF_HEADING.trashed, 0)
              AND (
                TASK.area = ?
                OR PROJECT.area = ?
                OR PROJECT_OF_HEADING.area = ?
              )
            ORDER BY TASK."index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, areaUUID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, areaUUID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, areaUUID, -1, sqliteTransient)

        var seen: Set<String> = []
        var titles: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let uuid = Self.stringValue(statement, column: 0) ?? ""
                guard seen.insert(uuid).inserted else {
                    continue
                }

                if let title = Self.stringValue(statement, column: 1) {
                    titles.append(title)
                }
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return titles
    }

    private func fetchTaggedTodoTitles(
        forTag tagUUID: String,
        in database: OpaquePointer
    ) throws -> [String] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT TASK.title
            FROM TMTaskTag AS TASK_TAG
            LEFT OUTER JOIN TMTask AS TASK ON TASK.uuid = TASK_TAG.tasks
            WHERE TASK_TAG.tags = ?
              AND TASK.type = 0
              AND TASK.status = 0
              AND TASK.trashed = 0
              AND TASK.rt1_recurrenceRule IS NULL
            ORDER BY TASK."index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, tagUUID, -1, sqliteTransient)

        return try fetchSingleStringColumn(from: statement, in: database)
    }

    private func fetchSingleStringColumn(
        from statement: OpaquePointer,
        in database: OpaquePointer
    ) throws -> [String] {
        var values: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                if let value = Self.stringValue(statement, column: 0) {
                    values.append(value)
                }
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return values
    }

    private func fetchChecklistItems(
        for uuid: String,
        in database: OpaquePointer
    ) throws -> [ThingsChecklistItem] {
        let statement = try prepareStatement(
            in: database,
            sql: """
            SELECT title,
                   CASE status
                       WHEN 3 THEN 'completed'
                       ELSE 'incomplete'
                   END AS status
            FROM TMChecklistItem
            WHERE task = ?
              AND IFNULL(leavesTombstone, 0) = 0
            ORDER BY "index"
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, uuid, -1, sqliteTransient)

        var items: [ThingsChecklistItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                items.append(
                    ThingsChecklistItem(
                        title: Self.stringValue(statement, column: 0) ?? "",
                        status: Self.stringValue(statement, column: 1) ?? "incomplete"
                    )
                )
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ThingsDatabaseError.stepFailed(Self.errorMessage(for: database))
            }
        }

        return items
    }

    private func withDatabase<T>(
        at path: String,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw ThingsDatabaseError.openFailed(
                database.map(Self.errorMessage(for:)) ?? "unknown error"
            )
        }
        defer { sqlite3_close(database) }

        return try operation(database)
    }

    private func prepareStatement(
        in database: OpaquePointer,
        sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard result == SQLITE_OK, let statement else {
            throw ThingsDatabaseError.prepareFailed(Self.errorMessage(for: database))
        }

        return statement
    }

    private func normalizeTarget(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func errorMessage(for database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    nonisolated private static func stringValue(
        _ statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard let textPointer = sqlite3_column_text(statement, column) else {
            return nil
        }

        return String(cString: textPointer)
    }

    nonisolated private static func todoStatus(from rawValue: Int32) -> CompletableTodoStatus {
        switch rawValue {
        case 0:
            return .incomplete
        case 3:
            return .completed
        default:
            return .canceled
        }
    }

    nonisolated private static func thingsDate(for date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return (year << 16) | (month << 12) | (day << 7)
    }

    nonisolated private static func thingsDate(forISODate value: String) throws -> Int {
        let components = value.split(separator: "-").map(String.init)
        guard
            components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2]),
            (1 ... 12).contains(month),
            (1 ... 31).contains(day)
        else {
            throw ThingsServiceError.invalidDate
        }

        return (year << 16) | (month << 12) | (day << 7)
    }

    private static func thingsDateToISODateExpression(column: String) -> String {
        let yearMask = 0b111111111110000000000000000
        let monthMask = 0b000000000001111000000000000
        let dayMask = 0b000000000000000111110000000

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

