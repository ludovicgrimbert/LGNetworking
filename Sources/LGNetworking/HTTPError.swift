//
//  HTTPError.swift
//  LGNetworking
//

import Foundation

/// Everything ``HTTPClient`` can fail with. Callers switch on it and map to their own
/// domain errors; nothing here knows about any particular API.
public enum HTTPError: Error, Sendable, Equatable {
    /// The request never completed: no network, timeout, DNS, cancelled…
    case transport(URLError)
    /// The transport answered with something that is not an `HTTPURLResponse`.
    case notHTTP
    /// The server answered outside the accepted range. The body is kept: many APIs put
    /// their reason there.
    case status(Int, body: Data)
    /// The body could not be decoded into the requested type.
    case decoding(String)

    public var statusCode: Int? {
        if case .status(let code, _) = self { return code }
        return nil
    }

    /// The failure was the request being cancelled, which callers usually swallow.
    public var isCancelled: Bool {
        if case .transport(let error) = self { return error.code == .cancelled }
        return false
    }
}

extension HTTPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .transport(let error): error.localizedDescription
        case .notHTTP: "The server did not answer over HTTP."
        case .status(let code, _): "The server answered HTTP \(code)."
        case .decoding(let detail): "The answer could not be read: \(detail)"
        }
    }
}
