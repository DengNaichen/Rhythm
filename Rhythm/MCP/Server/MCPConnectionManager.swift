import MCP
import Network
import OSLog

private let log = Logger.server

@MainActor
final class MCPConnectionManager {
    private let connectionID: UUID
    private let connection: NWConnection
    private let server: MCP.Server
    private let transport: NetworkTransport

    private weak var parentManager: ServerNetworkManager?

    init(connectionID: UUID, connection: NWConnection, parentManager: ServerNetworkManager) {
        self.connectionID = connectionID
        self.connection = connection
        self.parentManager = parentManager

        self.transport = NetworkTransport(
            connection: connection,
            logger: nil,
            reconnectionConfig: .disabled,
            bufferConfig: .unlimited
        )

        self.server = MCP.Server(
            name: Bundle.main.name ?? "Rhythm",
            version: Bundle.main.shortVersionString ?? "unknown",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
    }

    func start(approvalHandler: @escaping @Sendable (MCP.Client.Info) async -> Bool) async throws {
        try await server.start(transport: transport) { [weak self, connectionID] clientInfo, _ in
            let approved = await approvalHandler(clientInfo)

            guard approved else {
                await self?.parentManager?.removeConnection(connectionID)
                throw MCPError.connectionClosed
            }

            return
        }

        guard let parentManager else {
            throw MCPError.connectionClosed
        }

        await parentManager.registerHandlers(for: server, connectionID: connectionID)
        startHealthMonitoring()
    }

    func notifyToolListChanged() async {
        do {
            try await server.notify(ToolListChangedNotification.message())
        } catch {
            log.error("Failed to notify tools/list changed: \(error.localizedDescription)")

            if let mcpError = error as? MCPError, mcpError == .connectionClosed {
                await parentManager?.removeConnection(connectionID)
            } else if let nwError = error as? NWError,
                nwError.errorCode == 54 || nwError.errorCode == 57
            {
                await parentManager?.removeConnection(connectionID)
            }
        }
    }

    func stop() async {
        await server.stop()
        connection.cancel()
    }

    private func startHealthMonitoring() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while self.parentManager?.isRunning() == true {
                switch self.connection.state {
                case .ready, .setup, .preparing, .waiting:
                    break
                case .cancelled:
                    await self.parentManager?.removeConnection(self.connectionID)
                    return
                case .failed(let error):
                    log.error(
                        "Connection \(self.connectionID) failed: \(error.localizedDescription)"
                    )
                    await self.parentManager?.removeConnection(self.connectionID)
                    return
                @unknown default:
                    break
                }

                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}
