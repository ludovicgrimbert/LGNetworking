//
//  HTTPClient.swift
//  LGNetworking
//

import Foundation

/// Sends requests through an ``HTTPTransport`` and turns the outcome into an
/// ``HTTPResponse`` or an ``HTTPError``. That is all it does: building requests is the
/// caller's job (see the `URLRequest` helpers), reading bodies is the caller's job (see
/// ``HTTPResponse``). Cheap to create, safe to share.
public struct HTTPClient: Sendable {
    public let transport: any HTTPTransport
    /// The statuses ``send(_:)`` accepts. Anything else is an ``HTTPError/status(_:body:)``.
    public let acceptableStatuses: Range<Int>

    /// - Parameters:
    ///   - transport: `URLSession.bounded()` by default — short timeouts, no waiting for
    ///     connectivity. Pass your own session for cookies, redirects or caching policies,
    ///     or a scripted transport in tests.
    ///   - acceptableStatuses: 2xx by default.
    public init(transport: any HTTPTransport = URLSession.bounded(),
                acceptableStatuses: Range<Int> = 200..<300) {
        self.transport = transport
        self.acceptableStatuses = acceptableStatuses
    }

    /// Performs the request and requires an acceptable status.
    public func send(_ request: URLRequest) async throws(HTTPError) -> HTTPResponse {
        let response = try await perform(request)
        guard acceptableStatuses.contains(response.statusCode) else {
            throw .status(response.statusCode, body: response.data)
        }
        return response
    }

    /// Performs the request and hands back whatever HTTP status came, for callers that
    /// read meaning into non-2xx answers (a 401 that means "type the PIN", a 304…). Only
    /// transport failures and non-HTTP answers throw.
    public func perform(_ request: URLRequest) async throws(HTTPError) -> HTTPResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            throw .transport(error)
        } catch {
            throw .transport(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }
        guard let http = response as? HTTPURLResponse else { throw .notHTTP }
        return HTTPResponse(data: data, response: http)
    }

    /// ``send(_:)`` followed by a JSON decode of the body.
    public func send<T: Decodable>(_ request: URLRequest,
                                   decoding type: T.Type,
                                   decoder: JSONDecoder = JSONDecoder()) async throws(HTTPError) -> T {
        try await send(request).decode(type, decoder: decoder)
    }
}
