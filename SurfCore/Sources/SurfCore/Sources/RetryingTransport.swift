import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wraps any `HTTPTransport` and gives a failed request another go.
///
/// ## Why this exists
/// A forecast fetch issues two concurrent requests, and `async let` means either
/// one failing fails the whole screen. Measured against Open-Meteo from a WSL2
/// network stack, roughly a quarter of requests hung until the timeout — and a
/// phone on cellular at the beach is a worse network than that, not a better
/// one. Without a retry the app shows an error screen on a working connection.
///
/// ## What it deliberately does not retry
/// Retrying a request the server already answered clearly is how a rate limit
/// turns into a ban. Only failures that a second attempt could plausibly fix are
/// retried: transport-level errors, and the status codes that mean "not now"
/// (408, 429, 5xx). A `400` is a permanent answer about a malformed request —
/// notably the one the marine endpoint returns for Gulf of Eilat coordinates,
/// which must fail immediately rather than three times slowly.
///
/// Cancellation is never retried. When `async let` cancels a sibling request
/// because its partner failed, retrying it would defeat the cancellation.
public struct RetryingTransport: HTTPTransport {
    public struct Policy: Sendable {
        public let maxAttempts: Int
        public let baseDelay: Duration
        /// Each successive wait is multiplied by this. An integer because
        /// `Duration` multiplies by one exactly, and a `Double` multiplier makes
        /// the backoff schedule drift into unrepresentable fractions.
        public let multiplier: Int

        public init(maxAttempts: Int, baseDelay: Duration, multiplier: Int) {
            precondition(maxAttempts >= 1, "A policy must allow at least one attempt")
            self.maxAttempts = maxAttempts
            self.baseDelay = baseDelay
            self.multiplier = multiplier
        }

        /// Three attempts, waiting 0.4 s then 1.2 s. Worst case adds about 1.6 s
        /// of waiting to a fetch that was going to fail anyway, and rescues the
        /// common case of a single dropped connection.
        public static let standard = Policy(
            maxAttempts: 3, baseDelay: .milliseconds(400), multiplier: 3
        )

        /// One retry, after a full second. For Stormglass, whose free tier is
        /// about ten requests a day: a retry storm there does not degrade the
        /// service, it exhausts the entire daily budget.
        public static let frugal = Policy(
            maxAttempts: 2, baseDelay: .seconds(1), multiplier: 1
        )

        /// For callers that want the seam without the behaviour.
        public static let none = Policy(
            maxAttempts: 1, baseDelay: .zero, multiplier: 1
        )
    }

    private let wrapped: any HTTPTransport
    private let policy: Policy
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameter sleep: injected so the tests exercise the backoff schedule
    ///   without actually waiting through it.
    public init(
        wrapping wrapped: any HTTPTransport,
        policy: Policy = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.wrapped = wrapped
        self.policy = policy
        self.sleep = sleep
    }

    public func data(from url: URL, headers: [String: String]) async throws -> Data {
        var delay = policy.baseDelay
        var lastError: any Error

        var attempt = 1
        while true {
            do {
                return try await wrapped.data(from: url, headers: headers)
            } catch {
                lastError = error
                guard attempt < policy.maxAttempts, Self.isWorthRetrying(error) else {
                    throw lastError
                }
            }

            try await sleep(delay)
            delay = delay * policy.multiplier
            attempt += 1
        }
    }

    // MARK: - Retryability

    static func isWorthRetrying(_ error: any Error) -> Bool {
        if error is CancellationError { return false }

        if let source = error as? SourceError {
            switch source {
            case .badStatus(let code):
                // 408 request timeout, 429 too many requests, 5xx server-side.
                return code == 408 || code == 429 || (500..<600).contains(code)
            case .transport:
                return true
            case .malformedPayload, .unknownStation, .staleObservation:
                // The bytes arrived. Asking again gets the same bytes.
                return false
            }
        }

        // URLSession's own failures. Listed explicitly rather than defaulting to
        // "retry anything", so an unexpected error surfaces instead of being
        // silently attempted three times.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .badServerResponse:
                return true
            case .cancelled:
                return false
            default:
                return false
            }
        }

        return false
    }
}
