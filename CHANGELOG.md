# Changelog

All notable changes to this package. [Keep a Changelog](https://keepachangelog.com) format,
[SemVer](https://semver.org).

## [Unreleased]

### Added
- `LGNetworking.xcworkspace` with the `LGNetworkingExample` app: send a request through
  `HTTPClient` and read the response or the `HTTPError`; a scripted-transport switch shows
  the failure cases without a server.

## [1.0.0] - 2026-09-14

First release: the HTTP plumbing RemoteTV and Pampuko each wrote their own version of.

### Added
- `HTTPClient` — `send(_:)` (2xx, or configurable range, else `HTTPError.status`),
  `perform(_:)` (any status; only transport failures throw), `send(_:decoding:)`.
  Typed throws (`throws(HTTPError)`).
- `HTTPResponse` — `statusCode`, `isSuccess`, `header(_:)`, `headers`, `cookies`,
  `decode(_:decoder:)`, `jsonObject`.
- `HTTPError` — `.transport(URLError)`, `.notHTTP`, `.status(Int, body:)`, `.decoding(String)`;
  `statusCode`, `isCancelled`, `LocalizedError`.
- `HTTPTransport` — the one-method protocol `HTTPClient` sends through; `URLSession` conforms.
- `URLSession.bounded(requestTimeout:resourceTimeout:waitsForConnectivity:cookies:redirects:)` —
  8 s / 15 s by default, no waiting for connectivity, optional cookie jar.
- `RedirectPolicy(preservedHeaders:sameHostOnly:maximumRedirects:)` — re-applies named headers
  on redirect, on the same host only by default, bounded redirect count.
- `HTTPMethod`, `URLRequest(url:method:headers:body:)`, `URLRequest.json(url:… body:)`,
  `URLRequest.json(url:… object:)`, `adding(header:value:)`, `URLRequest.url(_:query:)`.
- `LGNetworkingTesting`: `StubTransport` (per-instance script, recorded requests, `failNext`,
  `reset`) and `ScriptedURLProtocol` (the same at `URLProtocol` level, process-wide).
