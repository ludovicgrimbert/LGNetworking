//
//  ScriptedURLProtocol.swift
//  LGNetworkingTesting
//

import Foundation
import LGNetworking

/// The same scripting as ``StubTransport``, at the `URLProtocol` level: for code that owns
/// a real `URLSession` (cookies, redirects, delegates) and cannot take an ``HTTPTransport``.
/// The script is global to the process, so tests using it must run serialised.
///
/// ```swift
/// let session = ScriptedURLProtocol.makeSession()
/// ScriptedURLProtocol.reset([.init(status: 401, headers: ["WWW-Authenticate": "Basic"])])
/// ```
public final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {
    public typealias Response = StubTransport.Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var script: [Response] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    /// Replaces the script and forgets the recorded requests.
    public static func reset(_ script: [Response]) {
        lock.withLock { self.script = script; recorded = [] }
    }

    /// The requests received so far, oldest first, bodies materialised.
    public static var requests: [URLRequest] { lock.withLock { recorded } }

    /// An ephemeral session that routes every request through the script. Cookies are
    /// left to the caller's code, as they would be with a hand-configured session.
    public static func makeSession(cookies: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedURLProtocol.self]
        configuration.timeoutIntervalForRequest = 8
        if !cookies {
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
        }
        return URLSession(configuration: configuration)
    }

    override public class func canInit(with request: URLRequest) -> Bool { true }
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        let response: Response? = Self.lock.withLock {
            Self.recorded.append(StubTransport.materialisingBody(of: request))
            return Self.script.isEmpty ? nil : Self.script.removeFirst()
        }
        guard let response, let url = request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                         headerFields: response.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}
}
