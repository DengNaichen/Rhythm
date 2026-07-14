import Foundation
import Observation

@MainActor
protocol CalendarSettingsServicing: AnyObject {
  func tools() -> [Tool]
  func authorizationState() -> CalendarAuthorizationState
  func requestAccess() async throws -> CalendarAuthorizationState
  func fetchUpcomingEvents(referenceDate: Date, daysAhead: Int) -> [CalendarEventRecord]
}

extension CalendarToolService: CalendarSettingsServicing {}

@MainActor
@Observable
final class CalendarSettingViewModel {
  @ObservationIgnored private let service: any CalendarSettingsServicing

  var isServiceEnabled: Bool = false
  private(set) var authorizationState: CalendarAuthorizationState
  private(set) var isWorking = false
  private(set) var isLoadingEvents = false
  private(set) var errorMessage: String?
  private(set) var events: [CalendarEventRecord] = []

  var tools: [Tool] {
    service.tools()
  }

  init(service: any CalendarSettingsServicing) {
    self.service = service

    let state = service.authorizationState()
    self.authorizationState = state
    self.isServiceEnabled = (state == .granted)
  }

  convenience init() {
    self.init(service: CalendarToolService())
  }

  var statusText: String {
    if isWorking {
      return "Requesting Access"
    }
    if isLoadingEvents {
      return "Loading Events"
    }

    switch (isServiceEnabled, authorizationState) {
    case (false, _):
      return "Inactive"
    case (true, .granted):
      return "Ready"
    case (true, .notDetermined):
      return "Needs Access"
    case (true, .denied):
      return "Access Denied"
    }
  }

  func load() async {
    refresh()

    if isServiceEnabled {
      await loadUpcomingEvents()
    }
  }

  func refresh() {
    let state = service.authorizationState()
    authorizationState = state
    isServiceEnabled = (state == .granted)

    if state != .granted {
      events = []
    }
  }

  func setServiceEnabled(_ enabled: Bool) {
    guard enabled else {
      isServiceEnabled = false
      errorMessage = nil
      events = []
      return
    }

    Task {
      await requestAccessAndLoad()
    }
  }

  func refreshEvents() {
    Task {
      await loadUpcomingEvents()
    }
  }

  func clearError() {
    errorMessage = nil
  }

  func dayText(for event: CalendarEventRecord) -> String {
    event.startAt.formatted(date: .abbreviated, time: .omitted)
  }

  func timeText(for event: CalendarEventRecord) -> String {
    if event.isAllDay {
      return "All Day"
    }

    let start = event.startAt.formatted(date: .omitted, time: .shortened)
    let end = event.endAt.formatted(date: .omitted, time: .shortened)
    return "\(start) - \(end)"
  }

  private func requestAccessAndLoad() async {
    guard !isWorking else {
      return
    }

    isWorking = true
    errorMessage = nil
    defer { isWorking = false }

    do {
      let state = try await service.requestAccess()
      authorizationState = state
      isServiceEnabled = (state == .granted)

      if state == .granted {
        await loadUpcomingEvents()
      } else {
        events = []
        errorMessage = "Calendar access was not granted."
      }
    } catch {
      let state = service.authorizationState()
      authorizationState = state
      isServiceEnabled = (state == .granted)
      events = []
      errorMessage = error.localizedDescription
    }
  }

  private func loadUpcomingEvents() async {
    guard isServiceEnabled, authorizationState == .granted else {
      events = []
      return
    }

    isLoadingEvents = true
    defer { isLoadingEvents = false }

    events = service.fetchUpcomingEvents(referenceDate: Date(), daysAhead: 7)
  }
}
