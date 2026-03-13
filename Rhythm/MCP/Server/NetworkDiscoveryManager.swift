import Network
import OSLog

private let log = Logger.server

@MainActor
final class NetworkDiscoveryManager {
    private let serviceType: String
    private let serviceDomain: String

    private var stateHandler: (@Sendable (NWListener.State) -> Void)?
    private var connectionHandler: (@Sendable (NWConnection) -> Void)?

    private(set) var listener: NWListener

    init(serviceType: String, serviceDomain: String) throws {
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain
        self.listener = try Self.makeListener(
            serviceType: serviceType,
            serviceDomain: serviceDomain
        )
    }

    func start(
        stateHandler: @escaping @Sendable (NWListener.State) -> Void,
        connectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) {
        self.stateHandler = stateHandler
        self.connectionHandler = connectionHandler

        applyHandlers(to: listener)
        listener.start(queue: .main)

        log.info("Started MCP listener advertising \(self.serviceType)")
    }

    func stop() {
        listener.cancel()
        log.info("Stopped MCP listener")
    }

    func restartWithRandomPort() throws {
        listener.cancel()
        listener = try Self.makeListener(
            serviceType: serviceType,
            serviceDomain: serviceDomain
        )

        applyHandlers(to: listener)
        listener.start(queue: .main)

        log.notice("Restarted MCP listener with a dynamic port")
    }

    private func applyHandlers(to listener: NWListener) {
        listener.stateUpdateHandler = stateHandler
        listener.newConnectionHandler = connectionHandler
    }

    private static func makeParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.includePeerToPeer = false

        if let ipOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options
        {
            ipOptions.version = .v4
        }

        return parameters
    }

    private static func makeListener(
        serviceType: String,
        serviceDomain: String
    ) throws -> NWListener {
        let listener = try NWListener(using: makeParameters())
        listener.service = NWListener.Service(type: serviceType, domain: serviceDomain)
        return listener
    }
}
