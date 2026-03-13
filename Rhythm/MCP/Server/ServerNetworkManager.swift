import MCP
import Network
import Ontology
import OSLog

private let serviceType = "_mcp._tcp"
private let serviceDomain = "local."
private let log = Logger.server

@MainActor
final class ServerNetworkManager: ServerRuntime {
    private let servicesByID: [String: any Service]

    private var isRunningState = false
    private var isEnabledState = true
    private var enabledServiceIDs: Set<String> = []
    private var clientAccessPolicy = ClientAccessPolicy()

    private var discoveryManager: NetworkDiscoveryManager?
    private var connections: [UUID: MCPConnectionManager] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]

    init(services: [any Service]) {
        self.servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })

        do {
            self.discoveryManager = try NetworkDiscoveryManager(
                serviceType: serviceType,
                serviceDomain: serviceDomain
            )
        } catch {
            log.error("Failed to initialize MCP network discovery: \(error.localizedDescription)")
        }
    }

    func start() async {
        guard !isRunningState else {
            return
        }

        guard let discoveryManager else {
            log.error("Cannot start MCP server: network discovery manager is unavailable")
            return
        }

        isRunningState = true

        discoveryManager.start(
            stateHandler: { [weak self] state in
                Task { @MainActor [weak self] in
                    await self?.handleListenerStateChange(state)
                }
            },
            connectionHandler: { [weak self] connection in
                Task { @MainActor [weak self] in
                    await self?.handleNewConnection(connection)
                }
            }
        )
    }

    func stop() async {
        guard isRunningState else {
            return
        }

        isRunningState = false

        let currentTasks = Array(connectionTasks.values)
        let currentConnections = Array(connections.values)

        connectionTasks.removeAll()
        connections.removeAll()

        for task in currentTasks {
            task.cancel()
        }

        for connection in currentConnections {
            await connection.stop()
        }

        discoveryManager?.stop()
    }

    func setEnabled(_ enabled: Bool) async {
        guard isEnabledState != enabled else {
            return
        }

        isEnabledState = enabled
        await notifyToolListChangedToAllConnections()
    }

    func setEnabledServices(_ serviceIDs: Set<String>) async {
        enabledServiceIDs = serviceIDs
        await notifyToolListChangedToAllConnections()
    }

    func setClientAccessPolicy(_ policy: ClientAccessPolicy) async {
        clientAccessPolicy = policy
    }

    func availableToolNames() async -> [String] {
        guard isEnabledState else {
            return []
        }

        return enabledServicesInOrder()
            .flatMap { _, service in service.tools().map(\.name) }
    }

    func isRunning() -> Bool {
        isRunningState
    }

    func removeConnection(_ id: UUID) async {
        if let task = connectionTasks.removeValue(forKey: id) {
            task.cancel()
        }

        guard let connectionManager = connections.removeValue(forKey: id) else {
            return
        }

        await connectionManager.stop()
    }

    func registerHandlers(for server: MCP.Server, connectionID: UUID) async {
        await server.withMethodHandler(ListPrompts.self) { _ in
            ListPrompts.Result(prompts: [])
        }

        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: [])
        }

        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard let self else {
                return ListTools.Result(tools: [])
            }

            return await self.makeListToolsResult()
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(
                    content: [MCP.Tool.Content.text("Server unavailable")],
                    isError: true
                )
            }

            return await self.handleCallTool(params, connectionID: connectionID)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) async {
        let connectionID = UUID()
        let connectionManager = MCPConnectionManager(
            connectionID: connectionID,
            connection: connection,
            parentManager: self
        )

        connections[connectionID] = connectionManager

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                self.connectionTasks.removeValue(forKey: connectionID)
            }

            do {
                try await connectionManager.start { [weak self] clientInfo in
                    guard let self else {
                        return false
                    }

                    return await self.isClientConnectionAllowed(clientInfo)
                }
            } catch {
                log.error(
                    "Failed to establish MCP connection \(connectionID): \(error.localizedDescription)"
                )
                await self.removeConnection(connectionID)
            }
        }

        connectionTasks[connectionID] = task
    }

    private func handleListenerStateChange(_ state: NWListener.State) async {
        switch state {
        case .ready:
            log.info("MCP listener is ready and advertising via Bonjour")
        case .setup:
            log.debug("MCP listener setting up")
        case .waiting(let error):
            log.warning("MCP listener waiting: \(error.localizedDescription)")

            if error.errorCode == 48 {
                await restartDiscovery(afterNanoseconds: 2_000_000_000)
            }
        case .failed(let error):
            log.error("MCP listener failed: \(error.localizedDescription)")
            await restartDiscovery(afterNanoseconds: 1_000_000_000)
        case .cancelled:
            log.info("MCP listener cancelled")
        @unknown default:
            log.warning("MCP listener entered an unknown state")
        }
    }

    private func restartDiscovery(afterNanoseconds nanoseconds: UInt64) async {
        guard isRunningState else {
            return
        }

        try? await Task.sleep(nanoseconds: nanoseconds)

        guard isRunningState else {
            return
        }

        do {
            try discoveryManager?.restartWithRandomPort()
        } catch {
            log.error("Failed to restart MCP listener: \(error.localizedDescription)")
        }
    }

    private func isClientConnectionAllowed(_ clientInfo: MCP.Client.Info) -> Bool {
        if let knownClient = KnownClient.matching(clientInfo.name) {
            return clientAccessPolicy.allows(knownClient)
        }

        return clientAccessPolicy.allowUnknownClients
    }

    private func enabledServicesInOrder() -> [(String, any Service)] {
        enabledServiceIDs
            .sorted()
            .compactMap { serviceID in
                guard let service = servicesByID[serviceID] else {
                    return nil
                }

                return (serviceID, service)
            }
    }

    private func makeListToolsResult() -> ListTools.Result {
        guard isEnabledState else {
            return ListTools.Result(tools: [])
        }

        let tools = enabledServicesInOrder()
            .flatMap { _, service in
                service.tools().map(\.mcpDefinition)
            }

        return ListTools.Result(tools: tools)
    }

    private func handleCallTool(_ params: CallTool.Parameters, connectionID: UUID) async
        -> CallTool.Result
    {
        guard isEnabledState else {
            return CallTool.Result(
                content: [MCP.Tool.Content.text("Rhythm is currently disabled.")],
                isError: true
            )
        }

        for (_, service) in enabledServicesInOrder() {
            do {
                guard let value = try await service.call(
                    tool: params.name,
                    with: params.arguments ?? [:]
                ) else {
                    continue
                }

                return CallTool.Result(
                    content: try makeToolContent(from: value),
                    isError: false
                )
            } catch {
                log.error(
                    "Tool \(params.name) failed for \(connectionID): \(error.localizedDescription)"
                )

                return CallTool.Result(
                    content: [MCP.Tool.Content.text("Error: \(error.localizedDescription)")],
                    isError: true
                )
            }
        }

        return CallTool.Result(
            content: [MCP.Tool.Content.text("Tool not found or service not enabled: \(params.name)")],
            isError: true
        )
    }

    private func makeToolContent(from value: Value) throws -> [MCP.Tool.Content] {
        if let (mimeType, data) = value.dataValue {
            if let mimeType, mimeType.hasPrefix("audio/") {
                return [.audio(data: data.base64EncodedString(), mimeType: mimeType)]
            }

            if let mimeType, mimeType.hasPrefix("image/") {
                return [.image(
                    data: data.base64EncodedString(),
                    mimeType: mimeType,
                    metadata: nil
                )]
            }
        }

        let encoder = JSONEncoder()
        encoder.userInfo[Ontology.DateTime.timeZoneOverrideKey] = TimeZone.current
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(value)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return [.text(text)]
    }

    private func notifyToolListChangedToAllConnections() async {
        for connection in connections.values {
            await connection.notifyToolListChanged()
        }
    }
}
