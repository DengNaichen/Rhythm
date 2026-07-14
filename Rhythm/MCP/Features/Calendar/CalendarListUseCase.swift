import Foundation

struct CalendarListUseCase {
  let runtime: EventKitRuntime

  func execute() throws -> [EventKitListDTO] {
    try requireCalendarAuthorization(runtime)
    return runtime.listEventCalendars().map(EventKitListDTO.init)
  }
}
