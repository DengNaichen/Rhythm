import Foundation
import Observation

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
    let remindersService: RemindersToolService
    let thingsService: ThingsToolService

    private(set) var serverStatus: ServerStatus = .starting
    private(set) var isServerEnabled: Bool
    private(set) var clientAccessPolicy: ClientAccessPolicy

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let runtime: any ServerRuntime

    private var enabledServiceIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.calendarService = CalendarToolService()
        self.remindersService = RemindersToolService()
        self.thingsService = ThingsToolService()
        self.isServerEnabled = Self.loadServerEnabled(from: defaults)
        self.enabledServiceIDs = Self.loadEnabledServiceIDs(from: defaults)
        self.clientAccessPolicy = Self.loadClientAccessPolicy(from: defaults)

        let services: [any Service] = [
            calendarService,
            remindersService,
            thingsService,
        ]

        self.runtime = ServerNetworkManager(services: services)

        Task {
            await bootstrap()
        }
    }

    var serverCommand: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/rhythm-server")
            .path
    }

    func isServiceEnabled(_ service: any Service) -> Bool {
        enabledServiceIDs.contains(service.id)
    }

    func setServiceEnabled(_ enabled: Bool, for service: any Service) async {
        if enabled {
            enabledServiceIDs.insert(service.id)
        } else {
            enabledServiceIDs.remove(service.id)
        }

        defaults.set(Array(enabledServiceIDs).sorted(), forKey: StorageKey.enabledServices)
        await runtime.setEnabledServices(enabledServiceIDs)
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

    func setServerEnabled(_ enabled: Bool) async {
        isServerEnabled = enabled
        defaults.set(enabled, forKey: StorageKey.serverEnabled)
        await runtime.setEnabled(enabled)
        serverStatus = enabled ? .running : .disabled
    }

    private func bootstrap() async {
        await runtime.setClientAccessPolicy(clientAccessPolicy)
        await runtime.setEnabledServices(enabledServiceIDs)
        await runtime.setEnabled(isServerEnabled)
        await runtime.start()
        serverStatus = isServerEnabled ? .running : .disabled
    }

    private static func loadServerEnabled(from defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: StorageKey.serverEnabled) != nil else {
            return true
        }

        return defaults.bool(forKey: StorageKey.serverEnabled)
    }

    private static func loadEnabledServiceIDs(from defaults: UserDefaults) -> Set<String> {
        let savedIDs = defaults.stringArray(forKey: StorageKey.enabledServices) ?? [
            "calendar",
            "reminders",
            "things",
        ]
        return Set(savedIDs)
    }

    private static func loadClientAccessPolicy(from defaults: UserDefaults) -> ClientAccessPolicy {
        let knownClients = Dictionary(uniqueKeysWithValues: KnownClient.allCases.map { client in
            let allowed: Bool
            if defaults.object(forKey: client.storageKey) != nil {
                allowed = defaults.bool(forKey: client.storageKey)
            } else {
                allowed = client.defaultValue
            }
            return (client, allowed)
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
