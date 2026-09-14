# LGNetworking

The thin HTTP layer shared by my apps: a client that turns `URLSession` answers into a
validated response or a typed error, a session with sane timeouts, a redirect policy that
keeps API keys on the same host, request builders, and scripted transports for tests.
Foundation only, iOS 17+, Swift 6.

```swift
.package(url: "https://github.com/ludovicgrimbert/LGNetworking", from: "1.0.0")
// products: "LGNetworking" for the app, "LGNetworkingTesting" for test targets
```

What it deliberately does not do: know your API. Building requests and reading bodies stay
in the app (`SonyClient`, `PrimClient`…); the package only removes the plumbing they all
copied — timeouts, status checks, redirect headers, test stubs.

## Usage

```swift
import LGNetworking

let client = HTTPClient()                       // URLSession.bounded(): 8 s / 15 s, no waiting for connectivity

// A validated call: 2xx or an HTTPError
let request = try URLRequest.json(url: url, headers: ["X-Auth-PSK": psk], object: ["method": "getPowerStatus", "id": 50])
let response = try await client.send(request)   // throws(HTTPError)
response.statusCode                             // 200
response.jsonObject?["result"]                  // [String: Any]
let status: PowerStatus = try response.decode() // Decodable

// A call whose non-2xx statuses carry meaning (401 = "type the PIN on the TV")
let answer = try await client.perform(request)  // only transport failures throw
switch answer.statusCode { case 200: …; case 401: …; default: … }
answer.cookies                                  // Set-Cookie parsed for the request's URL

// Errors
do { _ = try await client.send(request) }
catch let error as HTTPError {
    switch error {
    case .status(let code, let body): …         // outside the accepted range, body kept
    case .transport(let urlError): …            // timeout, offline, cancelled (error.isCancelled)
    case .notHTTP, .decoding: …
    }
}
```

### Sessions

```swift
// Custom timeouts, no cookie jar (credentials handled by hand)
let session = URLSession.bounded(requestTimeout: 8, cookies: false)

// Redirects: re-apply named headers, only when the redirect stays on the same host
let prim = URLSession.bounded(redirects: RedirectPolicy(preservedHeaders: ["apikey", "Accept"]))
let client = HTTPClient(transport: prim)
```

Anything conforming to `HTTPTransport` (one method, `data(for:)`) can stand in for the
session — that is how tests replace the network without a `URLProtocol`.

## Testing

```swift
import LGNetworkingTesting

let transport = StubTransport([.init(status: 200, body: "{\"result\":[]}"),
                               .init(status: 401, headers: ["WWW-Authenticate": "Basic"])])
let client = SonyClient(transport: transport)            // your code, taking an HTTPTransport
…
#expect(transport.requests.first?.value(forHTTPHeaderField: "X-Auth-PSK") == "1234")
transport.failNext(with: URLError(.timedOut))            // the next call fails
transport.reset([])                                      // an exhausted script = unreachable host
```

`StubTransport` is an instance: tests run in parallel without sharing state. For code that
must own a real `URLSession` (cookie jar, redirects), `ScriptedURLProtocol` offers the same
script at the `URLProtocol` level — its state is process-wide, so serialise those tests.

## Versions

- 1.0.0 — `HTTPClient`, `HTTPResponse`, `HTTPError`, `URLSession.bounded`, `RedirectPolicy`,
  `URLRequest` builders, `StubTransport`, `ScriptedURLProtocol`.
