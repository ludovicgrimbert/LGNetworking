//
//  HTTPClientTests.swift
//  LGNetworkingTests
//

import Foundation
import Testing
import LGNetworking
import LGNetworkingTesting

private let url = URL(string: "https://api.example.com/v1/items?a=1")!

@Suite("HTTPClient")
struct HTTPClientTests {

    @Test("send returns the body and the response on 2xx")
    func success() async throws {
        let transport = StubTransport([.init(status: 201, headers: ["X-Trace": "abc"], body: "{\"id\":7}")])
        let client = HTTPClient(transport: transport)
        let response = try await client.send(URLRequest(url: url))
        #expect(response.statusCode == 201)
        #expect(response.isSuccess)
        #expect(response.header("x-trace") == "abc")
        #expect(response.jsonObject?["id"] as? Int == 7)
        #expect(transport.requests.map(\.url) == [url])
    }

    @Test("send throws .status with the body outside the accepted range")
    func status() async {
        let transport = StubTransport([.init(status: 401, body: "{\"error\":\"key\"}")])
        let client = HTTPClient(transport: transport)
        await #expect(throws: HTTPError.status(401, body: Data("{\"error\":\"key\"}".utf8))) {
            try await client.send(URLRequest(url: url))
        }
    }

    @Test("perform hands back any status without throwing")
    func perform() async throws {
        let transport = StubTransport([.init(status: 401, headers: ["WWW-Authenticate": "Basic realm=\"tv\""])])
        let response = try await HTTPClient(transport: transport).perform(URLRequest(url: url))
        #expect(response.statusCode == 401)
        #expect(!response.isSuccess)
        #expect(response.header("WWW-Authenticate") == "Basic realm=\"tv\"")
    }

    @Test("a transport failure is .transport, with cancellation recognisable")
    func transportFailure() async {
        let transport = StubTransport()
        transport.failNext(with: URLError(.timedOut))
        let client = HTTPClient(transport: transport)
        await #expect(throws: HTTPError.transport(URLError(.timedOut))) { try await client.send(URLRequest(url: url)) }

        transport.failNext(with: URLError(.cancelled))
        do {
            _ = try await client.send(URLRequest(url: url))
            Issue.record("expected a throw")
        } catch {
            #expect(error.isCancelled)
        }

        // An exhausted script reads as an unreachable host, not a crash.
        await #expect(throws: HTTPError.transport(URLError(.cannotConnectToHost))) { try await client.send(URLRequest(url: url)) }
    }

    @Test("decoding goes through send, failures are .decoding")
    func decoding() async throws {
        struct Item: Decodable, Equatable { let id: Int }
        let transport = StubTransport([.init(status: 200, body: "{\"id\":3}"), .init(status: 200, body: "not json")])
        let client = HTTPClient(transport: transport)
        #expect(try await client.send(URLRequest(url: url), decoding: Item.self) == Item(id: 3))
        do {
            _ = try await client.send(URLRequest(url: url), decoding: Item.self)
            Issue.record("expected a throw")
        } catch {
            guard case .decoding = error else { Issue.record("expected .decoding, got \(error)"); return }
        }
    }

    @Test("a custom accepted range")
    func acceptedRange() async throws {
        let transport = StubTransport([.init(status: 304)])
        let client = HTTPClient(transport: transport, acceptableStatuses: 200..<400)
        #expect(try await client.send(URLRequest(url: url)).statusCode == 304)
    }

    @Test("cookies are parsed from the response for its URL")
    func cookies() async throws {
        let transport = StubTransport([.init(status: 200, headers: ["Set-Cookie": "auth=abc123; Path=/; Max-Age=1209600"])])
        let response = try await HTTPClient(transport: transport).send(URLRequest(url: url))
        let cookie = try #require(response.cookies.first)
        #expect(cookie.name == "auth")
        #expect(cookie.value == "abc123")
        #expect(response.headers["Set-Cookie"]?.hasPrefix("auth=") == true)
    }
}

@Suite("URLRequest builders")
struct URLRequestBuilderTests {

    @Test("method, headers and body in one call")
    func plain() {
        let request = URLRequest(url: url, method: .delete, headers: ["Accept": "application/json"], body: Data("x".utf8))
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.httpBody == Data("x".utf8))
    }

    @Test("Encodable and hand-built JSON bodies set the content type")
    func json() throws {
        struct Body: Encodable { let name: String }
        let encoded = try URLRequest.json(url: url, body: Body(name: "tv"))
        #expect(encoded.httpMethod == "POST")
        #expect(encoded.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: encoded.httpBody ?? Data(), as: UTF8.self) == "{\"name\":\"tv\"}")

        let object = try URLRequest.json(url: url, headers: ["X-Auth-PSK": "1234"], object: ["method": "getPowerStatus", "id": 50])
        let sent = try JSONSerialization.jsonObject(with: object.httpBody ?? Data()) as? [String: Any]
        #expect(sent?["method"] as? String == "getPowerStatus")
        #expect(object.value(forHTTPHeaderField: "X-Auth-PSK") == "1234")
        #expect(object.adding(header: "Cookie", value: "auth=1").value(forHTTPHeaderField: "Cookie") == "auth=1")
    }

    @Test("query items append to an existing query, nil values are skipped")
    func query() throws {
        let built = try #require(URLRequest.url(url, query: ["MonitoringRef": "STIF:1", "LineRef": nil, "b": "2"]))
        #expect(built.absoluteString == "https://api.example.com/v1/items?a=1&MonitoringRef=STIF:1&b=2")
    }
}

@Suite("Sessions and redirects")
struct SessionTests {

    @Test("the bounded session has short timeouts and does not wait for connectivity")
    func bounded() {
        let configuration = URLSession.bounded().configuration
        #expect(configuration.timeoutIntervalForRequest == 8)
        #expect(configuration.timeoutIntervalForResource == 15)
        #expect(configuration.waitsForConnectivity == false)
        #expect(configuration.httpShouldSetCookies == true)

        let noCookies = URLSession.bounded(requestTimeout: 3, cookies: false).configuration
        #expect(noCookies.timeoutIntervalForRequest == 3)
        #expect(noCookies.httpShouldSetCookies == false)
        #expect(noCookies.httpCookieAcceptPolicy == .never)
    }

    @Test("the redirect policy re-applies headers on the same host only")
    func redirectPolicy() throws {
        let policy = RedirectPolicy(preservedHeaders: ["apikey", "Accept"], maximumRedirects: 2)
        let original = URLRequest(url: URL(string: "https://prim.example.com/a")!, method: .get,
                                  headers: ["apikey": "secret", "Accept": "application/json", "X-Other": "1"])

        let sameHost = URLRequest(url: URL(string: "https://prim.example.com/b")!)
        let kept = try #require(policy.redirectedRequest(from: original, to: sameHost, redirectCount: 1))
        #expect(kept.value(forHTTPHeaderField: "apikey") == "secret")
        #expect(kept.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(kept.value(forHTTPHeaderField: "X-Other") == nil)

        let elsewhere = URLRequest(url: URL(string: "https://evil.example.org/b")!)
        let stripped = try #require(policy.redirectedRequest(from: original, to: elsewhere, redirectCount: 1))
        #expect(stripped.value(forHTTPHeaderField: "apikey") == nil)

        let anyHost = RedirectPolicy(preservedHeaders: ["apikey"], sameHostOnly: false)
        #expect(anyHost.redirectedRequest(from: original, to: elsewhere, redirectCount: 1)?.value(forHTTPHeaderField: "apikey") == "secret")

        #expect(policy.redirectedRequest(from: original, to: sameHost, redirectCount: 3) == nil)
    }

    @Test("the scripted URLProtocol drives a real URLSession")
    func scriptedProtocol() async throws {
        let session = ScriptedURLProtocol.makeSession()
        ScriptedURLProtocol.reset([.init(status: 200, body: "ok")])
        let client = HTTPClient(transport: session)
        let response = try await client.send(URLRequest(url: url, method: .post, body: Data("payload".utf8)))
        #expect(String(decoding: response.data, as: UTF8.self) == "ok")
        let request = try #require(ScriptedURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("payload".utf8))
    }
}
