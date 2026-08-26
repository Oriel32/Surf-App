import Foundation
import Testing
@testable import SurfCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A transport that fails a set number of times before succeeding, and records
/// every call. Enough to pin the retry behaviour without a network or a clock.
private actor FlakyTransport: HTTPTransport {
    private let failures: Int
    private let error: any Error
    private(set) var attempts = 0

    init(failuresBeforeSuccess: Int, error: any Error = SourceError.transport("dropped")) {
        self.failures = failuresBeforeSuccess
        self.error = error
    }

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        attempts += 1
        if attempts <= failures { throw error }
        return Data("ok".utf8)
    }

    var callCount: Int { attempts }
}

/// Records the backoff schedule instead of waiting through it.
private actor SleepRecorder {
    private(set) var waits: [Duration] = []
    func record(_ duration: Duration) { waits.append(duration) }
    var recorded: [Duration] { waits }
}

@Suite("Transport retry")
struct RetryingTransportTests {
    private let url = URL(string: "https://example.test/forecast")!

    private func makeTransport(
        _ flaky: FlakyTransport,
        policy: RetryingTransport.Policy = .standard,
        recorder: SleepRecorder? = nil
    ) -> RetryingTransport {
        RetryingTransport(wrapping: flaky, policy: policy) { duration in
            await recorder?.record(duration)
        }
    }

    @Test("A single dropped connection is retried and the fetch succeeds")
    func recoversFromOneFailure() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 1)
        let data = try await makeTransport(flaky).data(from: url, headers: [:])

        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(await flaky.callCount == 2)
    }

    @Test("A working connection is not retried")
    func doesNotRetryOnSuccess() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 0)
        _ = try await makeTransport(flaky).data(from: url, headers: [:])
        #expect(await flaky.callCount == 1)
    }

    @Test("Retries stop at the policy limit and the last error is thrown")
    func givesUpAfterMaxAttempts() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99)
        let transport = makeTransport(flaky)

        await #expect(throws: SourceError.transport("dropped")) {
            try await transport.data(from: url, headers: [:])
        }
        #expect(await flaky.callCount == 3)
    }

    @Test("Each wait is longer than the last")
    func backsOffExponentially() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99)
        let recorder = SleepRecorder()
        let transport = makeTransport(flaky, recorder: recorder)

        _ = try? await transport.data(from: url, headers: [:])

        let waits = await recorder.recorded
        #expect(waits.count == 2)
        #expect(waits.first == .milliseconds(400))
        #expect(waits.last == .milliseconds(1200))
    }

    /// The regression that matters most here: the marine endpoint answers 400
    /// for Gulf of Eilat coordinates. That is a permanent answer, and retrying
    /// it three times turns a fast correct failure into a slow one.
    @Test("A 400 is a permanent answer and is never retried")
    func doesNotRetryBadRequest() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99, error: SourceError.badStatus(400))
        let transport = makeTransport(flaky)

        await #expect(throws: SourceError.badStatus(400)) {
            try await transport.data(from: url, headers: [:])
        }
        #expect(await flaky.callCount == 1)
    }

    @Test("A payload that arrived and would not parse is not retried")
    func doesNotRetryMalformedPayload() async throws {
        let flaky = FlakyTransport(
            failuresBeforeSuccess: 99, error: SourceError.malformedPayload("bad json")
        )
        _ = try? await makeTransport(flaky).data(from: url, headers: [:])
        #expect(await flaky.callCount == 1)
    }

    @Test("Server-side and rate-limit statuses are retried", arguments: [408, 429, 500, 503])
    func retriesTransientStatuses(code: Int) async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 1, error: SourceError.badStatus(code))
        _ = try await makeTransport(flaky).data(from: url, headers: [:])
        #expect(await flaky.callCount == 2)
    }

    @Test("Client mistakes are not retried", arguments: [401, 403, 404, 422])
    func doesNotRetryClientErrors(code: Int) async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99, error: SourceError.badStatus(code))
        _ = try? await makeTransport(flaky).data(from: url, headers: [:])
        #expect(await flaky.callCount == 1)
    }

    @Test("A cancelled sibling request is not retried")
    func doesNotRetryCancellation() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99, error: CancellationError())
        _ = try? await makeTransport(flaky).data(from: url, headers: [:])
        #expect(await flaky.callCount == 1)
    }

    @Test("A timed-out connection is worth another go")
    func urlTimeoutIsRetryable() {
        #expect(RetryingTransport.isWorthRetrying(URLError(.timedOut)))
        #expect(RetryingTransport.isWorthRetrying(URLError(.networkConnectionLost)))
        #expect(!RetryingTransport.isWorthRetrying(URLError(.cancelled)))
    }

    /// Stormglass's free tier is about ten requests a day. A standard policy
    /// would spend a third of the daily budget on one unlucky fetch.
    @Test("The frugal policy allows exactly one retry")
    func frugalPolicyRetriesOnce() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99)
        _ = try? await makeTransport(flaky, policy: .frugal).data(from: url, headers: [:])
        #expect(await flaky.callCount == 2)
    }

    @Test("The none policy makes exactly one attempt")
    func nonePolicyDoesNotRetry() async throws {
        let flaky = FlakyTransport(failuresBeforeSuccess: 99)
        _ = try? await makeTransport(flaky, policy: .none).data(from: url, headers: [:])
        #expect(await flaky.callCount == 1)
    }
}
