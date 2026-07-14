import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service batch validation")
@MainActor
struct ThingsToolServiceBatchValidationTests {
  @Test("batch rejects an update without an ID before dispatch")
  func batchValidation() async throws {
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(builder: builder, callback: callback)
        .tools().first { $0.name == "things_batch" }
    )

    var caught = false
    do {
      _ = try await tool([
        "items": .array([
          .object([
            "type": .string("to-do"),
            "operation": .string("update"),
            "attributes": .object(["title": .string("Missing ID")]),
          ])
        ])
      ])
    } catch {
      caught = true
      #expect(error.localizedDescription.contains("ID is required"))
    }
    #expect(caught)
    #expect(builder.jsonRequests.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("batch rejects type-mismatched, operation-specific, and ignored nested fields")
  func batchStrictValidation() async throws {
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(builder: builder, callback: callback)
        .tools().first { $0.name == "things_batch" }
    )
    let invalidItems: [Value] = [
      .object([
        "type": .string("to-do"),
        "attributes": .object(["area": .string("Work")]),
      ]),
      .object([
        "type": .string("project"),
        "attributes": .object(["append-notes": .string("update only")]),
      ]),
      .object([
        "type": .string("project"),
        "attributes": .object([
          "items": .array([
            .object([
              "type": .string("to-do"),
              "attributes": .object([
                "title": .string("Nested"),
                "list": .string("Ignored"),
              ]),
            ])
          ])
        ]),
      ]),
    ]

    for item in invalidItems {
      do {
        _ = try await tool(["items": .array([item])])
        Issue.record("Expected strict batch validation to reject the item")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
    }
    #expect(builder.jsonRequests.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("batch rejects fields that Things would silently ignore")
  func batchIgnoredFieldValidation() async throws {
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(callback: callback).tools().first { $0.name == "things_batch" })
    let invalidItems: [Value] = [
      .object([
        "type": .string("to-do"),
        "attributes": .object(["completed": .bool(true), "canceled": .bool(true)]),
      ]),
      .object([
        "type": .string("project"),
        "attributes": .object([
          "completed": .bool(true),
          "items": .array([
            .object([
              "type": .string("to-do"),
              "attributes": .object(["title": .string("Incomplete")]),
            ])
          ]),
        ]),
      ]),
      .object([
        "type": .string("project"),
        "attributes": .object([
          "items": .array([
            .object([
              "type": .string("heading"),
              "attributes": .object(["title": .string("Phase"), "archived": .bool(true)]),
            ]),
            .object([
              "type": .string("to-do"),
              "attributes": .object(["title": .string("Incomplete")]),
            ]),
          ])
        ]),
      ]),
      .object([
        "type": .string("to-do"),
        "attributes": .object(["title": .string(String(repeating: "x", count: 4_001))]),
      ]),
      .object([
        "type": .string("to-do"),
        "attributes": .object(["creation-date": .string("2999-01-01T00:00:00Z")]),
      ]),
    ]

    for item in invalidItems {
      do {
        _ = try await tool(["items": .array([item])])
        Issue.record("Expected ignored-field validation to reject batch item")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
    }
    #expect(callback.urls.isEmpty)
  }
}
