import Foundation
import OSLog
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
  enum ServerStatus: String {
    case starting
    case running
    case stopped
    case disabled
  }

  private enum StorageKey {
    static let serverEnabled = "app.serverEnabled"
    static let enabledServices = "app.enabledServices"
  }

  let calendarService: CalendarToolService
  let hydrationService: HydrationToolService
  let thingsService: ThingsToolService

  private(set) var serverStatus: ServerStatus = .starting
  private(set) var isServerEnabled: Bool
  private(set) var visibleServiceConfigs: [ServiceConfig]
  private(set) var clientAccessPolicy: ClientAccessPolicy

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let runtime: any ServerRuntime

  private var serviceEnabledStates: [ServiceID: Bool]

  var hasEnabledServices: Bool {
    serviceEnabledStates.values.contains(true)
  }

  init(
    defaults: UserDefaults = .standard,
    autoStart: Bool = true
  ) {
    self.defaults = defaults
    self.calendarService = CalendarToolService()
    self.hydrationService = HydrationToolService()
    self.thingsService = ThingsToolService()

    let serviceConfigs = [
      ServiceConfig(
        id: .calendar,
        name: "Calendar",
        iconName: "calendar",
        color: .red,
        service: calendarService
      ),
      ServiceConfig(
        id: .hydration,
        name: "Hydration",
        iconName: "drop.fill",
        color: .blue,
        service: hydrationService
      ),
      ServiceConfig(
        id: .things,
        name: "Things",
        iconName: "checklist.checked",
        color: .teal,
        service: thingsService
      ),
    ]

    self.visibleServiceConfigs = serviceConfigs
    self.serviceEnabledStates = Self.loadServiceStates(
      from: defaults,
      serviceConfigs: serviceConfigs
    )
    self.clientAccessPolicy = Self.loadClientAccessPolicy(from: defaults)
    self.isServerEnabled = Self.loadServerEnabled(from: defaults)
    self.runtime = ServerNetworkManager(services: serviceConfigs.map(\.service))

    if autoStart {
      Task {
        await bootstrap()
      }
    }
  }

  var serverCommand: String {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/rhythm-server")
      .path
  }

  func serviceConfig(for serviceID: ServiceID) -> ServiceConfig? {
    visibleServiceConfigs.first(where: { $0.id == serviceID })
  }

  func isServiceEnabled(_ serviceID: ServiceID) -> Bool {
    serviceEnabledStates[serviceID] ?? false
  }

  func setServiceEnabled(_ enabled: Bool, for serviceID: ServiceID) async {
    guard serviceEnabledStates.keys.contains(serviceID) else {
      return
    }

    serviceEnabledStates[serviceID] = enabled
    defaults.set(enabled, forKey: serviceID.storageKey)
    defaults.set(Array(currentEnabledServiceIDs).sorted(), forKey: StorageKey.enabledServices)
    await runtime.setEnabledServices(currentEnabledServiceIDs)
  }

  func setKnownClient(_ client: KnownClient, allowed: Bool) async {
    clientAccessPolicy.setAllowed(allowed, for: client)
    defaults.set(allowed, forKey: client.storageKey)
    await runtime.setClientAccessPolicy(clientAccessPolicy)
  }

  func setAllowUnknownClients(_ allowed: Bool) async {
    clientAccessPolicy.allowUnknownClients = allowed
    defaults.set(allowed, forKey: ClientAccessStorageKey.allowUnknownClients)
    await runtime.setClientAccessPolicy(clientAccessPolicy)
  }

  func activateService(_ serviceID: ServiceID) async -> Bool {
    guard let service = service(for: serviceID) else {
      return false
    }

    if await service.isActivated() {
      return true
    }

    do {
      try await service.activate()
    } catch {
      Logger.server.error(
        "Failed to activate service \(serviceID.rawValue): \(error.localizedDescription)"
      )
    }

    return await service.isActivated()
  }

  func refreshActivationState(for serviceID: ServiceID, syncEnabledState: Bool) async -> Bool {
    guard let service = service(for: serviceID) else {
      return false
    }

    let activated = await service.isActivated()
    if syncEnabledState && !activated {
      await setServiceEnabled(false, for: serviceID)
    }

    return activated
  }

  func setServerEnabled(_ enabled: Bool) async {
    isServerEnabled = enabled
    defaults.set(enabled, forKey: StorageKey.serverEnabled)
    await runtime.setEnabled(enabled)
    serverStatus = enabled ? .running : .disabled
  }

  private func bootstrap() async {
    await reconcileActivationStates()
    await runtime.setClientAccessPolicy(clientAccessPolicy)
    await runtime.setEnabledServices(currentEnabledServiceIDs)
    await runtime.setEnabled(isServerEnabled)
    await runtime.start()
    serverStatus = isServerEnabled ? .running : .disabled
  }

  private func reconcileActivationStates() async {
    for config in visibleServiceConfigs where isServiceEnabled(config.id) {
      let activated = await config.service.isActivated()
      if !activated {
        serviceEnabledStates[config.id] = false
        defaults.set(false, forKey: config.id.storageKey)
      }
    }

    defaults.set(Array(currentEnabledServiceIDs).sorted(), forKey: StorageKey.enabledServices)
  }

  private var currentEnabledServiceIDs: Set<String> {
    Set(serviceEnabledStates.compactMap { $0.value ? $0.key.rawValue : nil })
  }

  private func service(for serviceID: ServiceID) -> (any Service)? {
    serviceConfig(for: serviceID)?.service
  }

  private static func loadServerEnabled(from defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: StorageKey.serverEnabled) != nil else {
      return true
    }

    return defaults.bool(forKey: StorageKey.serverEnabled)
  }

  private static func loadServiceStates(
    from defaults: UserDefaults,
    serviceConfigs: [ServiceConfig]
  ) -> [ServiceID: Bool] {
    let legacyEnabledServiceIDs = Set(
      defaults.stringArray(forKey: StorageKey.enabledServices) ?? [])

    return Dictionary(
      uniqueKeysWithValues: serviceConfigs.map { config in
        let value: Bool
        if defaults.object(forKey: config.id.storageKey) != nil {
          value = defaults.bool(forKey: config.id.storageKey)
        } else {
          value = legacyEnabledServiceIDs.contains(config.id.rawValue)
        }
        return (config.id, value)
      })
  }

  private static func loadClientAccessPolicy(from defaults: UserDefaults) -> ClientAccessPolicy {
    let knownClients = Dictionary(
      uniqueKeysWithValues: KnownClient.allCases.map { client in
        let value: Bool
        if defaults.object(forKey: client.storageKey) != nil {
          value = defaults.bool(forKey: client.storageKey)
        } else {
          value = client.defaultValue
        }
        return (client, value)
      })

    let allowUnknownClients: Bool
    if defaults.object(forKey: ClientAccessStorageKey.allowUnknownClients) != nil {
      allowUnknownClients = defaults.bool(forKey: ClientAccessStorageKey.allowUnknownClients)
    } else {
      allowUnknownClients = false
    }

    return ClientAccessPolicy(
      knownClients: knownClients,
      allowUnknownClients: allowUnknownClients
    )
  }
}
