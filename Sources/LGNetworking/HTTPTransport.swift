//
//  HTTPTransport.swift
//  LGNetworking
//

import Foundation

/// What ``HTTPClient`` needs from the network: one request in, bytes and a response out.
/// `URLSession` conforms as is; tests substitute a scripted transport (see
/// `LGNetworkingTesting`).
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}
