import Foundation

@MainActor
protocol ServerRuntime: AnyObject {
    func start() async
    func stop() async
    func setEnabled(_ enabled: Bool) async
    func setEnabledServices(_ serviceIDs: Set<String>) async
    func setClientAccessPolicy(_ policy: ClientAccessPolicy) async
    func availableToolNames() async -> [String]
}
