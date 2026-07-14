import Darwin
import Foundation
import Network

private let serviceType = "_mcp._tcp"
private let networkQueue = DispatchQueue(label: "NaichengDeng.Rhythm.rhythm-server")
private let heartbeatMagicBytes: [UInt8] = [0xF0, 0x9F, 0x92, 0x93]
private let heartbeatLength = 12

private func writeLog(_ message: String) {
  message.utf8CString.withUnsafeBufferPointer { buffer in
    guard let baseAddress = buffer.baseAddress else {
      return
    }
    fputs(baseAddress, stderr)
  }
}

private func makeParameters() -> NWParameters {
  let parameters = NWParameters.tcp
  parameters.acceptLocalOnly = true
  parameters.includePeerToPeer = false

  if let internetProtocol = parameters.defaultProtocolStack.internetProtocol
    as? NWProtocolIP.Options
  {
    internetProtocol.version = .v4
  }

  return parameters
}

private func launchContainingAppIfPossible() {
  let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
  var candidateURL = executableURL.deletingLastPathComponent()

  while candidateURL.path != "/" {
    if candidateURL.pathExtension == "app" {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-g", candidateURL.path]
      try? process.run()
      return
    }

    candidateURL.deleteLastPathComponent()
  }
}

private func posixError(_ code: Int32 = errno) -> NSError {
  NSError(
    domain: NSPOSIXErrorDomain,
    code: Int(code),
    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
  )
}

private enum BridgeError: LocalizedError {
  case connectionClosed
  case discoveryTimeout

  var errorDescription: String? {
    switch self {
    case .connectionClosed:
      return "Connection closed"
    case .discoveryTimeout:
      return "Service discovery timed out"
    }
  }
}

actor ResumptionGate {
  private var hasResumed = false

  func resumeIfNeeded() -> Bool {
    guard !hasResumed else {
      return false
    }

    hasResumed = true
    return true
  }
}

actor StdioProxy {
  private let endpoint: NWEndpoint
  private let parameters: NWParameters
  private let stdinBufferSize: Int
  private let networkBufferSize: Int

  private var connection: NWConnection?
  private var isRunning = false

  init(
    endpoint: NWEndpoint,
    parameters: NWParameters,
    stdinBufferSize: Int = 10 * 1024 * 1024,
    networkBufferSize: Int = 10 * 1024 * 1024
  ) {
    self.endpoint = endpoint
    self.parameters = parameters
    self.stdinBufferSize = stdinBufferSize
    self.networkBufferSize = networkBufferSize
  }

  func start() async throws {
    guard !isRunning else {
      return
    }

    isRunning = true

    let connection = NWConnection(to: endpoint, using: parameters)
    self.connection = connection
    connection.start(queue: networkQueue)

    try await waitUntilReady(connection)

    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await self.pipeStdinToNetwork(bufferSize: self.stdinBufferSize) }
        group.addTask { try await self.pipeNetworkToStdout(bufferSize: self.networkBufferSize) }

        _ = try await group.next()
        group.cancelAll()
      }
    } catch {
      stop()
      throw error
    }

    stop()
  }

  func stop() {
    isRunning = false
    connection?.cancel()
    connection = nil
  }

  private func waitUntilReady(_ connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { continuation in
      let gate = ResumptionGate()

      connection.stateUpdateHandler = { state in
        Task {
          switch state {
          case .ready:
            if await gate.resumeIfNeeded() {
              continuation.resume()
            }
          case .failed(let error):
            if await gate.resumeIfNeeded() {
              continuation.resume(throwing: error)
            }
          case .cancelled:
            if await gate.resumeIfNeeded() {
              continuation.resume(throwing: BridgeError.connectionClosed)
            }
          default:
            break
          }
        }
      }
    }
  }

  private func pipeStdinToNetwork(bufferSize: Int) async throws {
    try setNonBlocking(STDIN_FILENO)
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while true {
      guard isRunning, let connection else {
        throw BridgeError.connectionClosed
      }

      let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)

      if bytesRead == 0 {
        throw BridgeError.connectionClosed
      }

      if bytesRead < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK {
          try await Task.sleep(nanoseconds: 10_000_000)
          continue
        }

        throw posixError()
      }

      let chunk = Data(buffer[0..<Int(bytesRead)])

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
          content: chunk,
          completion: .contentProcessed { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume()
            }
          })
      }
    }
  }

  private func pipeNetworkToStdout(bufferSize: Int) async throws {
    while true {
      guard isRunning, let connection else {
        throw BridgeError.connectionClosed
      }

      let data = try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Data, Error>) in
        connection.receive(
          minimumIncompleteLength: 1,
          maximumLength: bufferSize
        ) { data, _, isComplete, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let data {
            continuation.resume(returning: data)
          } else if isComplete {
            continuation.resume(throwing: BridgeError.connectionClosed)
          } else {
            continuation.resume(returning: Data())
          }
        }
      }

      let processedData = stripHeartbeatPrefix(from: data)

      if processedData.isEmpty {
        try await Task.sleep(nanoseconds: 10_000_000)
        continue
      }

      try writeAll(processedData, to: STDOUT_FILENO)
    }
  }

  private func setNonBlocking(_ fileDescriptor: Int32) throws {
    let flags = fcntl(fileDescriptor, F_GETFL)
    guard flags >= 0 else {
      throw posixError()
    }

    guard fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
      throw posixError()
    }
  }

  private func stripHeartbeatPrefix(from data: Data) -> Data {
    guard data.count >= heartbeatMagicBytes.count else {
      return data
    }

    guard data.starts(with: heartbeatMagicBytes) else {
      return data
    }

    guard data.count >= heartbeatLength else {
      return Data()
    }

    return Data(data.dropFirst(heartbeatLength))
  }

  private func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
    var remainingData = data

    while !remainingData.isEmpty {
      let bytesWritten = remainingData.withUnsafeBytes { rawBuffer in
        write(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
      }

      if bytesWritten < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK {
          usleep(1_000)
          continue
        }

        throw posixError()
      }

      guard bytesWritten > 0 else {
        throw BridgeError.connectionClosed
      }

      remainingData.removeFirst(Int(bytesWritten))
    }
  }
}

actor BonjourBridgeService {
  private let parameters = makeParameters()

  private var browser: NWBrowser?
  private var proxy: StdioProxy?

  func run() async throws {
    launchContainingAppIfPossible()

    while true {
      do {
        let endpoint = try await discoverEndpoint()
        let proxy = StdioProxy(endpoint: endpoint, parameters: parameters)
        self.proxy = proxy
        try await proxy.start()
        return
      } catch BridgeError.connectionClosed {
        return
      } catch {
        writeLog("rhythm-server: \(error.localizedDescription)\n")
        try await Task.sleep(nanoseconds: 5_000_000_000)
      }
    }
  }

  func shutdown() async {
    browser?.cancel()
    await proxy?.stop()
  }

  private func discoverEndpoint() async throws -> NWEndpoint {
    let browser = NWBrowser(
      for: .bonjour(type: serviceType, domain: nil),
      using: parameters
    )
    self.browser = browser

    return try await withCheckedThrowingContinuation { continuation in
      let gate = ResumptionGate()

      let timeoutTask = Task {
        try await Task.sleep(nanoseconds: 30_000_000_000)
        if await gate.resumeIfNeeded() {
          browser.cancel()
          continuation.resume(throwing: BridgeError.discoveryTimeout)
        }
      }

      browser.stateUpdateHandler = { state in
        Task {
          switch state {
          case .failed(let error):
            if await gate.resumeIfNeeded() {
              timeoutTask.cancel()
              browser.cancel()
              continuation.resume(throwing: error)
            }
          default:
            break
          }
        }
      }

      browser.browseResultsChangedHandler = { results, _ in
        Task {
          guard !results.isEmpty else {
            return
          }

          let preferredResult =
            results.first {
              String(describing: $0.endpoint).localizedCaseInsensitiveContains("Rhythm")
            }
            ?? results.first

          guard let preferredResult else {
            return
          }

          if await gate.resumeIfNeeded() {
            timeoutTask.cancel()
            browser.cancel()
            continuation.resume(returning: preferredResult.endpoint)
          }
        }
      }

      browser.start(queue: networkQueue)
    }
  }
}

@main
enum RhythmServerCLI {
  static func main() async {
    let service = BonjourBridgeService()

    do {
      try await service.run()
    } catch {
      writeLog("rhythm-server terminated: \(error.localizedDescription)\n")
      await service.shutdown()
      exit(1)
    }
  }
}
