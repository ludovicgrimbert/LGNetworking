//
//  ContentView.swift
//  LGNetworkingExample
//

import SwiftUI
import LGNetworking
import LGNetworkingTesting

/// One request, one answer: type a URL, send it through `HTTPClient`, read what came back —
/// or what failed, as an `HTTPError`. The "scripted transport" switch swaps the network for
/// a `StubTransport`, the way a test would, so the error cases can be seen without a server.
struct ContentView: View {
    @State private var urlText = "https://httpbin.org/get"
    @State private var method: HTTPMethod = .get
    @State private var apiKey = ""
    @State private var acceptAnyStatus = false
    @State private var useStub = false
    @State private var stubScenario: StubScenario = .ok
    @State private var outcome: Outcome?
    @State private var isSending = false

    enum StubScenario: String, CaseIterable, Identifiable {
        case ok = "200 with JSON", unauthorized = "401", serverError = "500", timeout = "Timeout", offline = "Offline"
        var id: String { rawValue }
    }

    enum Outcome {
        case response(HTTPResponse, elapsed: Duration)
        case failure(HTTPError, elapsed: Duration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    TextField("URL", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Method", selection: $method) {
                        ForEach([HTTPMethod.get, .post, .delete], id: \.rawValue) { Text($0.rawValue).tag($0) }
                    }
                    TextField("apikey header (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("perform() — accept any status", isOn: $acceptAnyStatus)
                }

                Section {
                    Toggle("Scripted transport (no network)", isOn: $useStub)
                    if useStub {
                        Picker("Scenario", selection: $stubScenario) {
                            ForEach(StubScenario.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                } footer: {
                    Text(useStub
                         ? "A StubTransport answers instead of the network, exactly as in a unit test."
                         : "URLSession.bounded(): 8 s per request, 15 s total, no waiting for connectivity. The apikey header survives a same-host redirect only.")
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Text("Send")
                            if isSending { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isSending || URL(string: urlText) == nil)
                }

                if let outcome {
                    outcomeSection(outcome)
                }
            }
            .navigationTitle("LGNetworking")
        }
    }

    @ViewBuilder
    private func outcomeSection(_ outcome: Outcome) -> some View {
        switch outcome {
        case .response(let response, let elapsed):
            Section("Response · \(elapsed.formatted(.units(allowed: [.milliseconds])))") {
                LabeledContent("Status", value: "\(response.statusCode)")
                    .foregroundStyle(response.isSuccess ? .green : .orange)
                if let type = response.header("Content-Type") { LabeledContent("Content-Type", value: type) }
                LabeledContent("Bytes", value: "\(response.data.count)")
                if !response.cookies.isEmpty {
                    LabeledContent("Cookies", value: response.cookies.map(\.name).joined(separator: ", "))
                }
            }
            Section("Body") {
                Text(bodyPreview(response.data))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        case .failure(let error, let elapsed):
            Section("HTTPError · \(elapsed.formatted(.units(allowed: [.milliseconds, .seconds])))") {
                switch error {
                case .status(let code, let body):
                    LabeledContent("Case", value: ".status(\(code))").foregroundStyle(.red)
                    Text(bodyPreview(body)).font(.caption.monospaced())
                case .transport(let urlError):
                    LabeledContent("Case", value: error.isCancelled ? ".transport (cancelled)" : ".transport").foregroundStyle(.red)
                    Text(urlError.localizedDescription).font(.caption)
                case .notHTTP:
                    LabeledContent("Case", value: ".notHTTP").foregroundStyle(.red)
                case .decoding(let detail):
                    LabeledContent("Case", value: ".decoding").foregroundStyle(.red)
                    Text(detail).font(.caption)
                }
            }
        }
    }

    private func bodyPreview(_ data: Data) -> String {
        guard !data.isEmpty else { return "(empty)" }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: pretty.prefix(2000), as: UTF8.self)
        }
        return String(decoding: data.prefix(2000), as: UTF8.self)
    }

    // MARK: - Sending

    private func makeClient() -> HTTPClient {
        guard useStub else {
            let policy = RedirectPolicy(preservedHeaders: ["apikey", "Accept"])
            return HTTPClient(transport: URLSession.bounded(redirects: policy))
        }
        let transport = StubTransport()
        switch stubScenario {
        case .ok: transport.reset([.init(status: 200, headers: ["Content-Type": "application/json", "Set-Cookie": "session=abc; Path=/"],
                                         body: "{\"hello\":\"world\",\"method\":\"\(method.rawValue)\"}")])
        case .unauthorized: transport.reset([.init(status: 401, headers: ["WWW-Authenticate": "Basic"], body: "{\"error\":\"missing key\"}")])
        case .serverError: transport.reset([.init(status: 500, body: "<html>Internal Server Error</html>")])
        case .timeout: transport.failNext(with: URLError(.timedOut))
        case .offline: transport.failNext(with: URLError(.notConnectedToInternet))
        }
        return HTTPClient(transport: transport)
    }

    private func send() async {
        guard let url = URL(string: urlText) else { return }
        isSending = true
        defer { isSending = false }

        var headers = ["Accept": "application/json"]
        if !apiKey.isEmpty { headers["apikey"] = apiKey }
        let request: URLRequest
        if method == .post {
            request = (try? URLRequest.json(url: url, headers: headers, object: ["sent": Date.now.timeIntervalSince1970]))
                ?? URLRequest(url: url, method: method, headers: headers)
        } else {
            request = URLRequest(url: url, method: method, headers: headers)
        }

        let client = makeClient()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = acceptAnyStatus ? try await client.perform(request) : try await client.send(request)
            outcome = .response(response, elapsed: clock.now - start)
        } catch {
            outcome = .failure(error, elapsed: clock.now - start)
        }
    }
}

#Preview {
    ContentView()
}
