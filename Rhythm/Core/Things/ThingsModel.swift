//
//  ThingsModel.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//

import Foundation

struct ThingsTaskCreationRequest {
    var title: String
    var notes: String?
    var when: String?
    var deadline: String?
    var tags: [String]?
    var checklistItems: [String]?
    var listID: String?
    var listTitle: String?
    var heading: String?
    var headingID: String?
}

struct NormalizedThingsTaskCreationRequest {
    let title: String
    let notes: String?
    let when: String?
    let deadline: String?
    let tags: [String]
    let checklistItems: [String]
    let listID: String?
    let listTitle: String?
    let heading: String?
    let headingID: String?
}

enum ThingsTaskCreationValidationError: Error, LocalizedError {
    case blankTitle
    case invalidField(name: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .blankTitle:
            return "Task title must not be empty."
        case let .invalidField(name, reason):
            return "Invalid \(name): \(reason)"
        }
    }
}

extension ThingsTaskCreationRequest {
    func normalized() throws -> NormalizedThingsTaskCreationRequest {
        let normalizedTitle = Self.normalizeScalar(title)
        guard let normalizedTitle, !normalizedTitle.isEmpty else {
            throw ThingsTaskCreationValidationError.blankTitle
        }

        let normalizedNotes = Self.normalizeScalar(notes)
        let normalizedWhen = Self.normalizeScalar(when)
        let normalizedDeadline = Self.normalizeScalar(deadline)
        let normalizedListID = Self.normalizeScalar(listID)
        let normalizedListTitle = normalizedListID == nil ? Self.normalizeScalar(listTitle) : nil
        let normalizedHeadingID = Self.normalizeScalar(headingID)
        let normalizedHeading = normalizedHeadingID == nil ? Self.normalizeScalar(heading) : nil
        let normalizedTags = try Self.normalizeCollection(tags, fieldName: "tags")
        let normalizedChecklistItems = try Self.normalizeCollection(
            checklistItems,
            fieldName: "checklist_items"
        )

        return NormalizedThingsTaskCreationRequest(
            title: normalizedTitle,
            notes: normalizedNotes,
            when: normalizedWhen,
            deadline: normalizedDeadline,
            tags: normalizedTags,
            checklistItems: normalizedChecklistItems,
            listID: normalizedListID,
            listTitle: normalizedListTitle,
            heading: normalizedHeading,
            headingID: normalizedHeadingID
        )
    }

    private static func normalizeScalar(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeCollection(
        _ values: [String]?,
        fieldName: String
    ) throws -> [String] {
        guard let values else {
            return []
        }

        var normalizedValues: [String] = []
        normalizedValues.reserveCapacity(values.count)

        for rawValue in values {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ThingsTaskCreationValidationError.invalidField(
                    name: fieldName,
                    reason: "values must not be empty"
                )
            }

            normalizedValues.append(trimmed)
        }

        return normalizedValues
    }
}

struct ThingsChecklistItem: Encodable, Equatable {
    let title: String
    let status: String
}

struct ThingsTodo: Encodable, Equatable {
    let uuid: String
    let title: String
    let type: String
    let status: String?
    let list: String?
    let startDate: String?
    let deadline: String?
    let completedDate: String?
    let created: String?
    let modified: String?
    let notes: String?
    let areaTitle: String?
    let projectTitle: String?
    let headingTitle: String?
    let parentProjectStart: String?
    let tags: [String]
    let checklistItems: [ThingsChecklistItem]
    let todayIndex: Int
}

struct ThingsProject: Encodable, Equatable {
    let uuid: String
    let title: String
    let areaTitle: String?
    let notes: String?
    let created: String?
    let modified: String?
    let headingTitles: [String]
    let todoTitles: [String]
}

struct ThingsArea: Encodable, Equatable {
    let uuid: String
    let title: String
    let projectTitles: [String]
    let todoTitles: [String]
}

struct ThingsTag: Encodable, Equatable {
    let uuid: String
    let title: String
    let shortcut: String?
    let taggedTodoTitles: [String]
}

struct ThingsCollectionResponse<Item: Encodable>: Encodable {
    let count: Int
    let items: [Item]

    init(items: [Item]) {
        self.count = items.count
        self.items = items
    }
}

struct ThingsActionResult: Encodable {
    let message: String
    let id: String?
    let title: String?
}

struct ShowItemRequest: Equatable {
    let target: String
    let query: String?
    let filterTags: [String]?
}

enum ShowTarget: Equatable {
    case list(id: String)
    case item(id: String, displayTitle: String)
}

enum CompletableTodoStatus: String, Encodable, Equatable {
    case incomplete
    case completed
    case canceled
}

struct CompletableTodoReference: Equatable {
    let id: String
    let title: String
    let status: CompletableTodoStatus
}

enum ThingsResolutionError: Error, LocalizedError {
    case showTargetNotFound(String)
    case ambiguousShowTarget(String)
    case completableTodoNotFound(String)
    case ambiguousCompletableTodo(String)
    case todoAlreadyCompleted(String)
    case todoCanceled(String)

    var errorDescription: String? {
        switch self {
        case let .showTargetNotFound(target):
            return "No matching item found for target: \(target)"
        case let .ambiguousShowTarget(target):
            return "Multiple items matched target: \(target)"
        case let .completableTodoNotFound(target):
            return "No matching incomplete todo found for target: \(target)"
        case let .ambiguousCompletableTodo(target):
            return "Multiple todos matched target: \(target)"
        case let .todoAlreadyCompleted(title):
            return "Todo is already completed: \(title)"
        case let .todoCanceled(title):
            return "Todo is canceled and cannot be completed: \(title)"
        }
    }
}

enum ThingsServiceError: Error, LocalizedError {
    case invalidDate
    case listFiltersRequireListTarget
    case missingAuthToken
    case missingRequiredArgument(String)
    case invalidType(String, expected: String)

    var errorDescription: String? {
        switch self {
        case .invalidDate:
            return "Invalid date: expected YYYY-MM-DD"
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
