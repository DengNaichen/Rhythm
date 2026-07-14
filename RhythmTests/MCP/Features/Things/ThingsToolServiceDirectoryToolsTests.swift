import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Things tool service directory tools")
@MainActor
struct ThingsToolServiceDirectoryToolsTests {
  @Test("save_area and save_tag map nullable patches to automation")
  func directoryWriteMapping() async throws {
    let repository = ThingsRepositorySpy()
    repository.tags = [ThingsTestFixtures.existingTag, ThingsTestFixtures.parentTag]
    let automation = ThingsAutomationExecutorSpy()
    let service = makeThingsService(repository: repository, automation: automation)

    let saveArea = try #require(service.tools().first { $0.name == "things_save_area" })
    let areaResult = try await saveArea([
      "title": .string("  Work  "),
      "tags": .array([.string("Existing")]),
      "collapsed": .bool(true),
    ])
    let areaCommands = await automation.commands
    guard case .saveArea(let area) = try #require(areaCommands.first) else {
      Issue.record("Expected saveArea automation")
      return
    }
    #expect(area.id == nil)
    #expect(area.title == "Work")
    #expect(area.tags == .value(["Existing"]))
    #expect(area.collapsed == true)
    #expect(areaResult.objectValue?["confirmed"] == .bool(true))

    let saveTag = try #require(service.tools().first { $0.name == "things_save_tag" })
    do {
      _ = try await saveTag(["title": .string("existing")])
      Issue.record("Expected duplicate tag creation to be rejected")
    } catch {
      #expect(error.localizedDescription.contains("already exists"))
      #expect(error.localizedDescription.contains("provide its id"))
    }
    #expect(await automation.commands.count == 1)

    let tagResult = try await saveTag([
      "id": .string("tag:child"),
      "shortcut": .null,
      "parent": .string("Parent"),
    ])
    let directoryCommands = await automation.commands
    guard directoryCommands.count == 2,
      case .saveTag(let tag) = directoryCommands[1]
    else {
      Issue.record("Expected saveTag automation")
      return
    }
    #expect(tag.id == "tag:child")
    #expect(tag.shortcut == .clear)
    #expect(tag.parent == .value("tag:parent"))
    #expect(tagResult.objectValue?["ref"] == .string("tag:child"))
  }
}
