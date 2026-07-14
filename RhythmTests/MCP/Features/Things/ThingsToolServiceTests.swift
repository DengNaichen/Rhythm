import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service contract")
@MainActor
struct ThingsToolServiceTests {
  @Test("exposes the Linear-style tool contract and safety annotations")
  func toolContract() {
    let service = ThingsToolService(
      urlBuilder: ThingsURLBuilderSpy(),
      callbackExecutor: ThingsCallbackExecutorSpy(),
      repository: ThingsRepositorySpy()
    )
    let tools = service.tools()

    #expect(
      tools.map(\.name) == [
        "things_search",
        "things_fetch",
        "things_list_todos",
        "things_get_todo",
        "things_save_todo",
        "things_update_checklist",
        "things_list_headings",
        "things_get_heading",
        "things_list_projects",
        "things_get_project",
        "things_save_project",
        "things_batch",
        "things_list_areas",
        "things_save_area",
        "things_list_tags",
        "things_save_tag",
        "things_delete",
        "things_restore",
        "things_empty_trash",
        "things_log_completed",
        "things_show",
        "things_open_search",
        "things_version",
      ]
    )
    #expect(tools.count == 23)
    #expect(tools.allSatisfy { $0.inputSchema != nil })
    #expect(tools.allSatisfy { $0.annotations.openWorldHint == false })

    let readOnlyNames: Set<String> = [
      "things_search",
      "things_fetch",
      "things_list_todos",
      "things_get_todo",
      "things_list_headings",
      "things_get_heading",
      "things_list_projects",
      "things_get_project",
      "things_list_areas",
      "things_list_tags",
      "things_version",
    ]
    for tool in tools where readOnlyNames.contains(tool.name) {
      #expect(tool.annotations.readOnlyHint == true)
      #expect(tool.annotations.destructiveHint == nil)
    }

    for name in [
      "things_save_todo", "things_update_checklist", "things_save_project", "things_batch",
      "things_save_area", "things_save_tag", "things_delete", "things_restore",
      "things_empty_trash", "things_log_completed",
    ] {
      let tool = tools.first { $0.name == name }
      #expect(tool?.annotations.readOnlyHint == nil)
      #expect(tool?.annotations.destructiveHint == true)
      #expect(tool?.annotations.idempotentHint == false)
    }

    let show = tools.first { $0.name == "things_show" }
    #expect(show?.annotations.readOnlyHint == nil)
    #expect(show?.annotations.destructiveHint == false)
    #expect(show?.annotations.idempotentHint == true)

    for tool in tools {
      let schema = tool.mcpDefinition.inputSchema.objectValue
      #expect(schema?["type"] == .string("object"))
      #expect(schema?["additionalProperties"] == .bool(false))
    }
  }

  @Test("expanded tools expose closed schemas and correct safety hints")
  func expandedToolContract() throws {
    let tools = makeThingsService().tools()
    let expectedNames: Set<String> = [
      "things_update_checklist",
      "things_list_headings",
      "things_get_heading",
      "things_batch",
      "things_save_area",
      "things_save_tag",
      "things_delete",
      "things_restore",
      "things_empty_trash",
      "things_log_completed",
      "things_open_search",
      "things_version",
    ]

    let expanded = tools.filter { expectedNames.contains($0.name) }
    #expect(Set(expanded.map(\.name)) == expectedNames)
    #expect(
      expanded.allSatisfy { tool in
        tool.mcpDefinition.inputSchema.objectValue?["additionalProperties"] == .bool(false)
      })

    for name in ["things_list_headings", "things_get_heading", "things_version"] {
      let tool = try #require(expanded.first { $0.name == name })
      #expect(tool.annotations.readOnlyHint == true)
      #expect(tool.annotations.destructiveHint == nil)
    }
    for name in [
      "things_update_checklist", "things_batch", "things_save_area", "things_save_tag",
      "things_delete", "things_restore", "things_empty_trash", "things_log_completed",
    ] {
      let tool = try #require(expanded.first { $0.name == name })
      #expect(tool.annotations.destructiveHint == true)
      #expect(tool.annotations.readOnlyHint == nil)
    }
    let openSearch = try #require(expanded.first { $0.name == "things_open_search" })
    #expect(openSearch.annotations.destructiveHint == false)
    #expect(openSearch.annotations.idempotentHint == true)
  }
}
