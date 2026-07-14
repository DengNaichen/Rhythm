import Foundation
import JSONSchema
import MCP
import OrderedCollections
import Testing

@testable import Rhythm

@Suite("MCP tool input validation")
@MainActor
struct ToolInputValidatorTests {
  @Test("enforces required, unknown, nested type, enum, and array limits")
  func schemaEnforcement() async throws {
    var callCount = 0
    let tool = Tool(
      name: "validation_test",
      title: "Validation Test",
      description: "Validation Test",
      systemImage: "checkmark",
      inputSchema: .object(
        properties: [
          "mode": .string(enum: [.string("safe")]),
          "items": .array(items: .string(), minItems: 1, maxItems: 2),
        ],
        required: ["mode", "items"],
        additionalProperties: false
      )
    ) { _ in
      callCount += 1
      return true
    }

    let invalidInputs: [[String: Value]] = [
      ["items": .array([.string("one")])],
      ["mode": .string("unsafe"), "items": .array([.string("one")])],
      ["mode": .string("safe"), "items": .array([.int(1)])],
      [
        "mode": .string("safe"),
        "items": .array([.string("one"), .string("two"), .string("three")]),
      ],
      [
        "mode": .string("safe"), "items": .array([.string("one")]),
        "typo": .bool(true),
      ],
    ]

    for input in invalidInputs {
      do {
        _ = try await tool(input)
        Issue.record("Expected schema validation to reject input")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
    }
    #expect(callCount == 0)

    let result = try await tool([
      "mode": .string("safe"), "items": .array([.string("one")]),
    ])
    #expect(result == .bool(true))
    #expect(callCount == 1)
  }

  @Test("date-time format accepts the app's local and RFC 3339 forms")
  func lenientDateTimeFormat() async throws {
    let tool = Tool(
      name: "date_validation_test",
      title: "Date Validation Test",
      description: "Date Validation Test",
      systemImage: "calendar",
      inputSchema: .object(
        properties: ["value": .string(format: .dateTime)],
        required: ["value"],
        additionalProperties: false
      )
    ) { _ in true }

    let validValues = [
      "2026-07-13",
      "2024-02-29",
      "2026-07-13T10:00",
      "2026-07-13T10:00:00",
      "2026-07-13 10:00:00.123456789",
      "2026-07-13T10:00:00Z",
      "2026-07-13T18:00:00+08:00",
      "2026-07-13T18:00:00+0800",
      "2026-07-13T10:00:00+14:00",
    ]
    for value in validValues {
      do {
        let result = try await tool(["value": .string(value)])
        #expect(result == .bool(true), "Unexpected result for valid date-time: \(value)")
      } catch {
        Issue.record("Valid date-time was rejected: \(value); error: \(error)")
      }
    }

    let invalidValues = [
      "not-a-date",
      "2026-02-29",
      "2026-13-01",
      "2026-07-13T24:00:00",
      "2026-07-13T10:60:00",
      "2026-07-13T10:00:60",
      "2026-07-13T10:00.123",
      "2026-07-13T10:00:00+14:01",
      "2026-07-13T10:00:00+24:00",
      "2026-07-13T10:00:00Ztrailing",
    ]
    for value in invalidValues {
      do {
        _ = try await tool(["value": .string(value)])
        Issue.record("Invalid date-time was accepted: \(value)")
      } catch {
        #expect(
          error.localizedDescription.contains("date-time"),
          "Unexpected validation error for invalid date-time: \(value); error: \(error)"
        )
      }
    }
  }

  @Test("email format rejects malformed alarm addresses")
  func emailFormat() async throws {
    var callCount = 0
    let tool = Tool(
      name: "email_validation_test",
      title: "Email Validation Test",
      description: "Email Validation Test",
      systemImage: "envelope",
      inputSchema: .object(
        properties: ["value": .string(format: .email)],
        required: ["value"],
        additionalProperties: false
      )
    ) { _ in
      callCount += 1
      return true
    }

    for value in ["person@example.com", "alerts+calendar@sub.example.com"] {
      _ = try await tool(["value": .string(value)])
    }

    for value in ["missing-at", "@example.com", "person@", "a@@example.com", "a b@example.com"] {
      do {
        _ = try await tool(["value": .string(value)])
        Issue.record("Invalid email was accepted: \(value)")
      } catch {
        #expect(error.localizedDescription.contains("email"))
      }
    }
    #expect(callCount == 2)
  }
}
