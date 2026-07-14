import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service navigation tools")
@MainActor
struct ThingsToolServiceNavigationToolsTests {
  @Test("things_show rejects direct and resolved headings before dispatch")
  func showRejectsHeadings() async throws {
    let repository = ThingsRepositorySpy()
    repository.resolvedShowTarget = ThingsReference(
      id: "heading:heading-1",
      title: "Phase"
    )
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(repository: repository, builder: builder, callback: callback)
        .tools().first { $0.name == "things_show" }
    )

    let invalidInputs: [[String: Value]] = [
      ["target": .string("heading:heading-1")],
      ["target": .string("heading:heading-1"), "quick_find": .bool(true)],
      ["target": .string("heading-12345678901234567890")],
      ["target": .string("heading-12345678901234567890"), "quick_find": .bool(true)],
      ["target": .string("Phase")],
    ]
    for input in invalidInputs {
      do {
        _ = try await tool(input)
        Issue.record("Expected Things heading navigation to be rejected")
      } catch {
        #expect(
          error.localizedDescription.contains("do not support headings")
            || error.localizedDescription.contains("quick_find=false")
        )
      }
    }
    #expect(builder.showIDs.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("things_show rejects unsupported Quick Find IDs and todo filters")
  func showURLContractValidation() async throws {
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy()
    let tool = try #require(
      makeThingsService(builder: builder, callback: callback)
        .tools().first { $0.name == "things_show" }
    )
    let invalidInputs: [[String: Value]] = [
      ["target": .string("todo:todo-1"), "quick_find": .bool(true)],
      [
        "target": .string("todo:todo-1"),
        "filter_tags": .array([.string("Existing")]),
      ],
      ["target": .string("today"), "filter_tags": .array([.string("One,Two")])],
    ]
    for input in invalidInputs {
      do {
        _ = try await tool(input)
        Issue.record("Expected unsupported show URL combination to be rejected")
      } catch {
        #expect(!error.localizedDescription.isEmpty)
      }
    }
    #expect(builder.showIDs.isEmpty)
    #expect(callback.urls.isEmpty)
  }

  @Test("open_search and version map callback responses")
  func navigationAndVersionMapping() async throws {
    let builder = ThingsURLBuilderSpy()
    let callback = ThingsCallbackExecutorSpy(
      responses: [
        thingsCallback(["opened": ["true"]]),
        thingsCallback([
          "x-things-scheme-version": ["2"],
          "x-things-client-version": ["3.21.5"],
        ]),
      ]
    )
    let service = makeThingsService(builder: builder, callback: callback)

    let openSearch = try #require(service.tools().first { $0.name == "things_open_search" })
    let searchResult = try await openSearch(["query": .string("  roadmap  ")])
    #expect(builder.searchQueries == ["roadmap"])
    #expect(searchResult.objectValue?["action"] == .string("search"))
    #expect(searchResult.objectValue?["target"] == .string("roadmap"))
    #expect(searchResult.objectValue?["confirmed"] == .bool(true))

    let version = try #require(service.tools().first { $0.name == "things_version" })
    let versionResult = try await version([:])
    #expect(builder.versionCallCount == 1)
    #expect(versionResult.objectValue?["scheme_version"] == .string("2"))
    #expect(versionResult.objectValue?["client_version"] == .string("3.21.5"))
    #expect(versionResult.objectValue?["confirmed"] == .bool(true))
  }
}
