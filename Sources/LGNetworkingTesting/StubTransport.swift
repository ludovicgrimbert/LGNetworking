//
//  StubTransport.swift
//  LGNetworkingTesting
//

import Foundation
import LGNetworking

/// A scripted ``HTTPTransport``: answers requests in order from a queue of responses and
/// records every request it received, so a test can assert on URL, method, headers and
/// body. When the script runs out, the transport fails as an unreachable host.
///
/// ```swift
/// let transport = StubTransport([.init(status: 200, body: "{\"ok\":true}")])
/// let client = HTTPClient(transport: transport)
/// _ = try await client.send(request)
/// #expect(transport.requests.first?.url == url)
/// ```
public final class StubTransport: HTTPTransport, @unchecked Sendable {
    public struct Response: Sendable {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        public init(status: Int, headers: [String: String] = [:], body: String) {
            self.init(status: status, headers: headers, body: Data(body.utf8))
        }
    }

    private let lock = NSLock()
    private var script: [Response]
    private var failures: [URLError] = []
    private var recorded: [URLRequest] = []

    public init(_ script: [Response] = []) {
        self.script = script
    }

    /// The requests received so far, oldest first. Bodies set through `httpBodyStream`
    /// are read back into `httpBody`.
    public var requests: [URLRequest] { lock.withLock { recorded } }

    /// Replaces the script and forgets the recorded requests.
    public func reset(_ script: [Response]) {
        lock.withLock { self.script = script; failures = []; recorded = [] }
    }

    /// The next request fails with this error instead of getting a response.
    public func failNext(with error: URLError) {
        lock.withLock { failures.append(error) }
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (response, failure): (Response?, URLError?) = lock.withLock {
            recorded.append(Self.materialisingBody(of: request))
            if !failures.isEmpty { return (nil, failures.removeFirst()) }
            return (script.isEmpty ? nil : script.removeFirst(), nil)
        }
        if let failure { throw failure }
        guard let response, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                         headerFields: response.headers) else {
            throw URLError(.cannotConnectToHost)
        }
        return (response.body, http)
    }

    static func materialisingBody(of request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        var request = request
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        request.httpBody = data
        return request
    }
}
