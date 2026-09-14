//
//  URLRequest+Build.swift
//  LGNetworking
//

import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

extension URLRequest {
    /// A request in one expression: method, headers and body together.
    public init(url: URL, method: HTTPMethod, headers: [String: String] = [:], body: Data? = nil) {
        self.init(url: url)
        httpMethod = method.rawValue
        for (field, value) in headers { setValue(value, forHTTPHeaderField: field) }
        httpBody = body
    }

    /// A request whose body is `value` encoded as JSON, with `Content-Type: application/json`.
    public static func json<T: Encodable>(url: URL,
                                          method: HTTPMethod = .post,
                                          headers: [String: String] = [:],
                                          body value: T,
                                          encoder: JSONEncoder = JSONEncoder()) throws -> URLRequest {
        var request = URLRequest(url: url, method: method, headers: headers, body: try encoder.encode(value))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// A request whose body is a JSON object built by hand (`[String: Any]`), for APIs
    /// whose payloads are not worth a `Codable` type — JSON-RPC calls, for instance.
    public static func json(url: URL,
                            method: HTTPMethod = .post,
                            headers: [String: String] = [:],
                            object: Any) throws -> URLRequest {
        var request = URLRequest(url: url, method: method, headers: headers,
                                 body: try JSONSerialization.data(withJSONObject: object))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// The same request with one more header — handy after a builder.
    public func adding(header field: String, value: String) -> URLRequest {
        var request = self
        request.setValue(value, forHTTPHeaderField: field)
        return request
    }

    /// The URL with query items appended, or nil if the URL cannot be taken apart.
    public static func url(_ base: URL, query: [String: String?]) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url
    }
}
