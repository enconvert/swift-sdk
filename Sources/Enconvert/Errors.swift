/** Enconvert SDK errors. */

import Foundation

/// Errors thrown by the Enconvert SDK.
///
/// Mirrors the Node SDK's exception hierarchy (`EnconvertError` / `APIError`
/// / `AuthenticationError` / `QuotaError` / `RateLimitError`) as a single
/// enum, which is the idiomatic Swift shape for a small closed error set.
public enum EnconvertError: Error, Equatable, Sendable {
    /// HTTP 401 or 403 — invalid or missing API key.
    case authentication(message: String)
    /// HTTP 402 — plan feature not enabled or monthly quota exhausted.
    case quota(message: String)
    /// HTTP 429 — rate limit exceeded.
    case rateLimit(message: String)
    /// Any other HTTP error response (`statusCode` is the raw HTTP status).
    case api(statusCode: Int, message: String)
    /// Client-side validation failure (missing API key, unsupported
    /// conversion pair, invalid option combination, ...) raised before any
    /// network request is made.
    case invalidArgument(String)

    /// The HTTP status code, when this error originated from a response.
    public var statusCode: Int? {
        switch self {
        case .authentication: return 401
        case .quota: return 402
        case .rateLimit: return 429
        case .api(let statusCode, _): return statusCode
        case .invalidArgument: return nil
        }
    }

    /// The human-readable error message (without the `[status]` prefix).
    public var message: String {
        switch self {
        case .authentication(let message): return message
        case .quota(let message): return message
        case .rateLimit(let message): return message
        case .api(_, let message): return message
        case .invalidArgument(let message): return message
        }
    }
}

extension EnconvertError: CustomStringConvertible {
    /// Matches the Node SDK's `APIError` string form: `[<status>] <message>`.
    public var description: String {
        if let statusCode {
            return "[\(statusCode)] \(message)"
        }
        return message
    }
}

extension EnconvertError: LocalizedError {
    public var errorDescription: String? { description }
}
