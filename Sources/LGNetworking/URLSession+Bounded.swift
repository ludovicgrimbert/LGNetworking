//
//  URLSession+Bounded.swift
//  LGNetworking
//

import Foundation

extension URLSession {
    /// A session that gives up in seconds instead of the 60 s default: a device that is off
    /// or an API that hangs must fail while the user is still looking.
    ///
    /// - Parameters:
    ///   - requestTimeout: idle time between two packets before failing (default 8 s).
    ///   - resourceTimeout: total time for the whole exchange (default 15 s).
    ///   - waitsForConnectivity: false by default — fail now rather than wait for a network.
    ///   - cookies: whether the session stores and sends cookies. Turn it off when the
    ///     caller handles credentials by hand.
    ///   - redirects: what to carry over when the server redirects; nil keeps the system
    ///     behaviour (headers other than `Authorization` follow, `Authorization` is dropped
    ///     on a cross-host redirect).
    public static func bounded(requestTimeout: TimeInterval = 8,
                               resourceTimeout: TimeInterval = 15,
                               waitsForConnectivity: Bool = false,
                               cookies: Bool = true,
                               redirects: RedirectPolicy? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = waitsForConnectivity
        if !cookies {
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
        }
        guard let redirects else { return URLSession(configuration: configuration) }
        return URLSession(configuration: configuration,
                          delegate: RedirectDelegate(policy: redirects),
                          delegateQueue: nil)
    }
}

/// What happens to the original request's headers when the server answers 3xx.
///
/// `URLSession` follows redirects on its own but rebuilds the request, and API keys sent
/// as custom headers do not always survive — the classic "401 after redirect". The policy
/// re-applies named headers from the original request. By default only when the redirect
/// stays on the same host, so a key is never handed to a third-party domain.
public struct RedirectPolicy: Sendable, Equatable {
    /// Header fields copied from the original request onto the redirected one.
    public var preservedHeaders: [String]
    /// When true (default), headers are preserved only if the new URL has the same host
    /// as the original; a redirect elsewhere gets the system's rebuilt request.
    public var sameHostOnly: Bool
    /// Maximum redirects followed before giving up with `URLError(.httpTooManyRedirects)`.
    public var maximumRedirects: Int

    public init(preservedHeaders: [String], sameHostOnly: Bool = true, maximumRedirects: Int = 5) {
        self.preservedHeaders = preservedHeaders
        self.sameHostOnly = sameHostOnly
        self.maximumRedirects = maximumRedirects
    }

    /// The redirected request as this policy wants it, or nil to stop following. Public so
    /// code that follows redirects by hand can apply the same rules.
    public func redirectedRequest(from original: URLRequest?, to proposed: URLRequest, redirectCount: Int) -> URLRequest? {
        guard redirectCount <= maximumRedirects else { return nil }
        guard let original else { return proposed }
        if sameHostOnly, original.url?.host?.lowercased() != proposed.url?.host?.lowercased() {
            return proposed
        }
        var request = proposed
        for field in preservedHeaders {
            if let value = original.value(forHTTPHeaderField: field) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        return request
    }
}

/// Applies a ``RedirectPolicy`` to every task of a session.
final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let policy: RedirectPolicy
    private let redirectCounts = Counter()

    init(policy: RedirectPolicy) {
        self.policy = policy
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let count = redirectCounts.increment(task.taskIdentifier)
        let next = policy.redirectedRequest(from: task.originalRequest, to: request, redirectCount: count)
        if next == nil { task.cancel() }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        redirectCounts.forget(task.taskIdentifier)
    }

    /// Redirects seen per task, behind a lock: the delegate is called from the session's queue.
    private final class Counter: Sendable {
        private let lock = NSLock()
        nonisolated(unsafe) private var counts: [Int: Int] = [:]

        func increment(_ task: Int) -> Int {
            lock.withLock {
                counts[task, default: 0] += 1
                return counts[task]!
            }
        }

        func forget(_ task: Int) {
            lock.withLock { counts[task] = nil }
        }
    }
}
