//
//  HTTPResponse.swift
//  LGNetworking
//

import Foundation

/// A completed HTTP exchange: the body and the response, with the status and the headers
/// one step closer than on `HTTPURLResponse`.
public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    public var statusCode: Int { response.statusCode }
    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    /// The header's value, matched case-insensitively as HTTP requires.
    public func header(_ field: String) -> String? {
        response.value(forHTTPHeaderField: field)
    }

    /// All headers whose keys and values are strings — the shape `HTTPCookie.cookies(with…)`
    /// and friends want.
    public var headers: [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
    }

    /// The `Set-Cookie` headers of the response, parsed for its URL.
    public var cookies: [HTTPCookie] {
        guard let url = response.url else { return [] }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
    }

    /// Decodes the body; a failure is an ``HTTPError/decoding(_:)`` carrying the decoder's
    /// message, so a caller can log what was wrong with the payload.
    public func decode<T: Decodable>(_ type: T.Type = T.self,
                                     decoder: JSONDecoder = JSONDecoder()) throws(HTTPError) -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    /// The body as a JSON object (`[String: Any]`), or nil when it is not one.
    public var jsonObject: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
