import Foundation
import Testing

@testable import Rhythm

@Suite("Things callback executor")
@MainActor
struct ThingsCallbackExecutorTests {
  @Test("Success callback returns Things IDs and replaces caller callbacks")
  func successCallback() async throws {
    let opener = CallbackTestOpener()
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .seconds(2),
      opener: opener
    )
    let command = try #require(
      URL(string: "things:///add?title=Milk&x-success=https%3A%2F%2Fexample.com%2Fsteal")
    )

    let task = Task {
      try await executor.execute(command)
    }
    let openedURL = await opener.nextURL()
    let openedComponents = try #require(
      URLComponents(url: openedURL, resolvingAgainstBaseURL: false)
    )
    #expect(openedComponents.queryItems?.filter { $0.name == "x-success" }.count == 1)
    #expect(openedComponents.queryItems?.first { $0.name == "title" }?.value == "Milk")

    var callback = try callbackComponents(named: "x-success", in: openedComponents)
    callback.queryItems?.append(
      contentsOf: [
        URLQueryItem(name: "x-things-id", value: "todo-one,todo-two"),
        URLQueryItem(name: "x-things-ids", value: #"["todo-three","todo-one"]"#),
      ]
    )
    #expect(await executor.handle(try #require(callback.url)))

    let success = try await task.value
    #expect(success.thingsIDs == ["todo-one", "todo-two", "todo-three"])
    #expect(success.parameters["rhythm-request-id"] == nil)
  }

  @Test("Error and cancel callbacks fail the pending request")
  func errorAndCancelCallbacks() async throws {
    let opener = CallbackTestOpener()
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .seconds(2),
      opener: opener
    )
    let command = try #require(URL(string: "things:///update?id=123&title=Milk"))

    let errorTask = Task { try await executor.execute(command) }
    let errorCommand = await opener.nextURL()
    var errorCallback = try callbackComponents(
      named: "x-error",
      in: try #require(URLComponents(url: errorCommand, resolvingAgainstBaseURL: false))
    )
    errorCallback.queryItems?.append(
      contentsOf: [
        URLQueryItem(name: "errorCode", value: "401"),
        URLQueryItem(name: "errorMessage", value: "Bad token"),
      ]
    )
    #expect(await executor.handle(try #require(errorCallback.url)))
    do {
      _ = try await errorTask.value
      Issue.record("Expected the Things error callback to fail")
    } catch let error as ThingsCallbackExecutorError {
      #expect(error == .thingsError(code: "401", message: "Bad token"))
    }

    let cancelTask = Task { try await executor.execute(command) }
    let cancelCommand = await opener.nextURL()
    let cancelCallback = try callbackComponents(
      named: "x-cancel",
      in: try #require(URLComponents(url: cancelCommand, resolvingAgainstBaseURL: false))
    )
    #expect(await executor.handle(try #require(cancelCallback.url)))
    do {
      _ = try await cancelTask.value
      Issue.record("Expected the Things cancel callback to fail")
    } catch let error as ThingsCallbackExecutorError {
      #expect(error == .canceledByThings)
    }
  }

  @Test("Missing callback times out")
  func callbackTimeout() async throws {
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .milliseconds(20),
      opener: CallbackTestOpener()
    )
    let command = try #require(URL(string: "things:///add?title=Milk"))

    do {
      _ = try await executor.execute(command)
      Issue.record("Expected the Things callback request to time out")
    } catch let error as ThingsCallbackExecutorError {
      #expect(error == .timedOut)
    }
  }

  @Test("Open failures and unrelated callback URLs are rejected")
  func openFailureAndInvalidCallback() async throws {
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      opener: CallbackTestOpener(openResult: false)
    )
    let command = try #require(URL(string: "things:///add?title=Milk"))

    do {
      _ = try await executor.execute(command)
      Issue.record("Expected opening the Things URL to fail")
    } catch let error as ThingsCallbackExecutorError {
      #expect(error == .failedToOpen)
    }

    let unrelated = try #require(URL(string: "https://example.com/success"))
    #expect(await !executor.handle(unrelated))
  }

  @Test("Caller cancellation is prompt and releases its pending slot")
  func callerCancellation() async throws {
    let opener = SuspendedCallbackTestOpener()
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .seconds(2),
      maximumPendingRequests: 1,
      opener: opener
    )
    let command = try #require(URL(string: "things:///add?title=First"))
    let task = Task { try await executor.execute(command) }
    let canceledCommand = await opener.nextURL()

    let safetyRelease = Task {
      do {
        try await Task.sleep(for: .milliseconds(500))
      } catch {
        return
      }
      await opener.releaseAll()
    }
    let clock = ContinuousClock()
    let started = clock.now
    task.cancel()

    do {
      _ = try await task.value
      Issue.record("Expected caller cancellation to fail the callback request")
    } catch is CancellationError {
      // Expected.
    }
    let elapsed = started.duration(to: clock.now)
    #expect(elapsed < .milliseconds(250))

    await opener.releaseAll()
    safetyRelease.cancel()

    let replacement = Task { try await executor.execute(command, timeout: .seconds(2)) }
    let replacementCommand = await opener.nextURL()
    var lateCallback = try callbackComponents(
      named: "x-success",
      in: try #require(URLComponents(url: canceledCommand, resolvingAgainstBaseURL: false))
    )
    lateCallback.queryItems?.append(URLQueryItem(name: "x-things-id", value: "stale"))
    #expect(await executor.handle(try #require(lateCallback.url)))

    var success = try callbackComponents(
      named: "x-success",
      in: try #require(URLComponents(url: replacementCommand, resolvingAgainstBaseURL: false))
    )
    success.queryItems?.append(URLQueryItem(name: "x-things-id", value: "replacement"))
    #expect(await executor.handle(try #require(success.url)))
    #expect(try await replacement.value.thingsIDs == ["replacement"])
  }

  @Test("Late and duplicate callbacks cannot affect a newer request")
  func lateAndDuplicateCallbacks() async throws {
    let opener = CallbackTestOpener()
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .milliseconds(20),
      maximumPendingRequests: 1,
      opener: opener
    )
    let command = try #require(URL(string: "things:///add?title=Milk"))

    let timedOutTask = Task { try await executor.execute(command) }
    let timedOutCommand = await opener.nextURL()
    do {
      _ = try await timedOutTask.value
      Issue.record("Expected the first request to time out")
    } catch let error as ThingsCallbackExecutorError {
      #expect(error == .timedOut)
    }

    let replacementTask = Task { try await executor.execute(command, timeout: .seconds(2)) }
    let replacementCommand = await opener.nextURL()
    var lateCallback = try callbackComponents(
      named: "x-success",
      in: try #require(URLComponents(url: timedOutCommand, resolvingAgainstBaseURL: false))
    )
    lateCallback.queryItems?.append(URLQueryItem(name: "x-things-id", value: "stale"))
    #expect(await executor.handle(try #require(lateCallback.url)))

    var replacementCallback = try callbackComponents(
      named: "x-success",
      in: try #require(URLComponents(url: replacementCommand, resolvingAgainstBaseURL: false))
    )
    replacementCallback.queryItems?.append(URLQueryItem(name: "x-things-id", value: "current"))
    let replacementURL = try #require(replacementCallback.url)
    #expect(await executor.handle(replacementURL))
    #expect(await executor.handle(replacementURL))
    #expect(try await replacementTask.value.thingsIDs == ["current"])
  }

  @Test("Concurrent requests are routed by request ID")
  func concurrentRouting() async throws {
    let opener = CallbackTestOpener()
    let executor = ThingsCallbackExecutor(
      callbackScheme: "rhythm-test",
      defaultTimeout: .seconds(2),
      opener: opener
    )
    let commandA = try #require(URL(string: "things:///add?title=A"))
    let commandB = try #require(URL(string: "things:///add?title=B"))
    let taskA = Task { try await executor.execute(commandA) }
    let taskB = Task { try await executor.execute(commandB) }
    let first = await opener.nextURL()
    let second = await opener.nextURL()
    let commands = try Dictionary(
      uniqueKeysWithValues: [first, second].map { url in
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let title = try #require(components.queryItems?.first { $0.name == "title" }?.value)
        return (title, components)
      }
    )

    var callbackB = try callbackComponents(named: "x-success", in: try #require(commands["B"]))
    callbackB.queryItems?.append(URLQueryItem(name: "x-things-id", value: "id-b"))
    #expect(await executor.handle(try #require(callbackB.url)))

    var callbackA = try callbackComponents(named: "x-success", in: try #require(commands["A"]))
    callbackA.queryItems?.append(URLQueryItem(name: "x-things-id", value: "id-a"))
    #expect(await executor.handle(try #require(callbackA.url)))

    #expect(try await taskA.value.thingsIDs == ["id-a"])
    #expect(try await taskB.value.thingsIDs == ["id-b"])
  }

  private func callbackComponents(
    named name: String,
    in commandComponents: URLComponents
  ) throws -> URLComponents {
    let value = try #require(commandComponents.queryItems?.first { $0.name == name }?.value)
    return try #require(URLComponents(string: value))
  }
}

private actor CallbackTestOpener: ThingsCallbackURLOpening {
  private let openResult: Bool
  private var queuedURLs: [URL] = []
  private var waiters: [CheckedContinuation<URL, Never>] = []

  init(openResult: Bool = true) {
    self.openResult = openResult
  }

  func open(_ url: URL) async -> Bool {
    if waiters.isEmpty {
      queuedURLs.append(url)
    } else {
      waiters.removeFirst().resume(returning: url)
    }
    return openResult
  }

  func nextURL() async -> URL {
    if !queuedURLs.isEmpty {
      return queuedURLs.removeFirst()
    }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

private actor SuspendedCallbackTestOpener: ThingsCallbackURLOpening {
  private var queuedURLs: [URL] = []
  private var urlWaiters: [CheckedContinuation<URL, Never>] = []
  private var openWaiters: [CheckedContinuation<Bool, Never>] = []

  func open(_ url: URL) async -> Bool {
    if urlWaiters.isEmpty {
      queuedURLs.append(url)
    } else {
      urlWaiters.removeFirst().resume(returning: url)
    }
    return await withCheckedContinuation { continuation in
      openWaiters.append(continuation)
    }
  }

  func nextURL() async -> URL {
    if !queuedURLs.isEmpty {
      return queuedURLs.removeFirst()
    }
    return await withCheckedContinuation { continuation in
      urlWaiters.append(continuation)
    }
  }

  func releaseAll() {
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters {
      waiter.resume(returning: true)
    }
  }
}
