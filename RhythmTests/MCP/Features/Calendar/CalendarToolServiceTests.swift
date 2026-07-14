import EventKit
import Foundation
import MCP
import Testing

@testable import Rhythm

@Suite("Calendar tool service contract")
@MainActor
struct CalendarToolServiceTests {
  @Test("exposes seven closed tools with correct safety annotations")
  func toolContract() throws {
    let tools = makeCalendarService(runtime: EventKitRuntimeSpy()).tools()

    #expect(
      tools.map(\.name) == [
        "calendar_calendars_list",
        "calendar_events_fetch",
        "calendar_events_get",
        "calendar_events_create",
        "calendar_events_update",
        "calendar_events_delete",
        "calendar_free_busy",
      ]
    )
    #expect(tools.count == 7)
    #expect(tools.allSatisfy { $0.inputSchema != nil })
    #expect(
      tools.allSatisfy {
        $0.mcpDefinition.inputSchema.objectValue?["additionalProperties"] == .bool(false)
      }
    )

    for name in [
      "calendar_calendars_list",
      "calendar_events_fetch",
      "calendar_events_get",
      "calendar_free_busy",
    ] {
      let tool = try #require(tools.first { $0.name == name })
      #expect(tool.annotations.readOnlyHint == true)
      #expect(tool.annotations.destructiveHint == nil)
      #expect(tool.annotations.openWorldHint == false)
    }

    let create = try #require(tools.first { $0.name == "calendar_events_create" })
    #expect(create.annotations.readOnlyHint == nil)
    #expect(create.annotations.destructiveHint == false)
    #expect(create.annotations.idempotentHint == nil)
    #expect(create.annotations.openWorldHint == true)

    let update = try #require(tools.first { $0.name == "calendar_events_update" })
    #expect(update.annotations.destructiveHint == true)
    #expect(update.annotations.idempotentHint == true)
    #expect(update.annotations.openWorldHint == true)

    let delete = try #require(tools.first { $0.name == "calendar_events_delete" })
    #expect(delete.annotations.destructiveHint == true)
    #expect(delete.annotations.idempotentHint == false)
    #expect(delete.annotations.openWorldHint == true)
  }

  @Test("declares operation-specific required fields")
  func requiredFields() throws {
    let service = makeCalendarService(runtime: EventKitRuntimeSpy())

    #expect(try requiredFields(of: "calendar_calendars_list", service: service).isEmpty)
    #expect(try requiredFields(of: "calendar_events_fetch", service: service).isEmpty)
    #expect(try requiredFields(of: "calendar_events_get", service: service) == ["id"])
    #expect(
      try requiredFields(of: "calendar_events_create", service: service)
        == ["end_at", "start_at", "title"]
    )
    #expect(try requiredFields(of: "calendar_events_update", service: service) == ["id"])
    #expect(
      try requiredFields(of: "calendar_events_delete", service: service) == ["confirm", "id"]
    )
    #expect(
      try requiredFields(of: "calendar_free_busy", service: service) == ["from", "to"]
    )

    for name in [
      "calendar_events_get",
      "calendar_events_update",
      "calendar_events_delete",
    ] {
      let tool = try requireCalendarTool(name, service: service)
      let properties = try #require(
        tool.mcpDefinition.inputSchema.objectValue?["properties"]?.objectValue
      )
      #expect(properties["occurrence_start"] != nil)
      #expect(properties["original_start_at"] != nil)
    }
  }

  @Test("maps calendar metadata and rejects write-only authorization")
  func calendarListAndAuthorization() async throws {
    let runtime = EventKitRuntimeSpy()
    runtime.calendars = [
      CalendarTestFixtures.writableCalendar,
      CalendarTestFixtures.readOnlyCalendar,
    ]
    let result = try CalendarListUseCase(runtime: runtime).execute()

    #expect(result.map(\.id) == ["calendar-work", "calendar-holidays"])
    #expect(result[0].isEditable)
    #expect(result[1].isSubscribed)

    runtime.authorizationStatus = .writeOnly
    let service = makeCalendarService(runtime: runtime)
    #expect(!(await service.isActivated()))
    #expect(service.authorizationState() == .denied)
    #expect(try await service.requestAccess() == .denied)

    do {
      _ = try CalendarListUseCase(runtime: runtime).execute()
      Issue.record("Expected write-only access to be rejected for the full Calendar service")
    } catch {
      #expect(error as? ServiceToolError == .unauthorized(service: "Calendar"))
    }
  }

  private func requiredFields(
    of toolName: String,
    service: CalendarToolService
  ) throws -> [String] {
    let tool = try requireCalendarTool(toolName, service: service)
    let values = tool.mcpDefinition.inputSchema.objectValue?["required"]?.arrayValue ?? []
    return values.compactMap(\.stringValue).sorted()
  }
}
