// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LGNetworking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        /// The HTTP client, the bounded session, the redirect policy, the request builders.
        /// Foundation only.
        .library(name: "LGNetworking", targets: ["LGNetworking"]),
        /// Scripted transports for tests. Link it from test targets only.
        .library(name: "LGNetworkingTesting", targets: ["LGNetworkingTesting"]),
    ],
    targets: [
        .target(name: "LGNetworking"),
        .target(name: "LGNetworkingTesting", dependencies: ["LGNetworking"]),
        .testTarget(name: "LGNetworkingTests", dependencies: ["LGNetworking", "LGNetworkingTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
