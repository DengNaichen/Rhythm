//
//  ThingsURLBuilder.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//


import AppKit
import Foundation

nonisolated protocol ThingsURLBuilding {
    func addTodoURL(for request: NormalizedThingsTaskCreationRequest) throws -> URL
    func showURL(id: String, query: String?, filterTags: [String]?) throws -> URL
    func completeTodoURL(id: String, authToken: String) throws -> URL
}

nonisolated protocol ThingsURLExecuting {
    func execute(_ url: URL) throws
}

nonisolated enum ThingsURLBuilderError: Error, LocalizedError {
    case invalidURL(String)
    case failedToOpen(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            return "Failed to build Things URL: \(value)"
        case let .failedToOpen(url):
            return "Failed to open Things URL: \(url.absoluteString)"
        }
    }
}

nonisolated struct ThingsURLBuilder: ThingsURLBuilding {
    func addTodoURL(for request: NormalizedThingsTaskCreationRequest) throws -> URL {
        var queryItems: [(String, String)] = [
            ("title", request.title)
        ]

        if let notes = request.notes {
            queryItems.append(("notes", notes))
        }

        if let when = request.when {
            queryItems.append(("when", when))
        }

        if let deadline = request.deadline {
            queryItems.append(("deadline", deadline))
        }

        if !request.tags.isEmpty {
            queryItems.append(("tags", request.tags.joined(separator: ",")))
        }

        if !request.checklistItems.isEmpty {
            queryItems.append(("checklist-items", request.checklistItems.joined(separator: "\n")))
        }

        if let listID = request.listID {
            queryItems.append(("list-id", listID))
        } else if let listTitle = request.listTitle {
            queryItems.append(("list", listTitle))
        }

        if let headingID = request.headingID {
            queryItems.append(("heading-id", headingID))
        } else if let heading = request.heading {
            queryItems.append(("heading", heading))
        }

        return try buildURL(command: "add", queryItems: queryItems)
    }

    func showURL(id: String, query: String?, filterTags: [String]?) throws -> URL {
        var queryItems: [(String, String)] = [("id", id)]

        if let query, !query.isEmpty {
            queryItems.append(("query", query))
        }

        if let filterTags, !filterTags.isEmpty {
            queryItems.append(("filter", filterTags.joined(separator: ",")))
        }

        return try buildURL(command: "show", queryItems: queryItems)
    }

    func completeTodoURL(id: String, authToken: String) throws -> URL {
        try buildURL(
            command: "update",
            queryItems: [
                ("id", id),
                ("completed", "true"),
                ("auth-token", authToken),
            ]
        )
    }

    private func buildURL(command: String, queryItems: [(String, String)]) throws -> URL {
        let encodedQuery = queryItems
            .map { key, value in
                "\(key)=\(Self.encode(value))"
            }
            .joined(separator: "&")

        let urlString = "things:///\(command)?\(encodedQuery)"
        guard let url = URL(string: urlString) else {
            throw ThingsURLBuilderError.invalidURL(urlString)
        }

        return url
    }

    private static func encode(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}

nonisolated struct WorkspaceThingsURLExecutor: ThingsURLExecuting {
    func execute(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw ThingsURLBuilderError.failedToOpen(url)
        }
    }
}
