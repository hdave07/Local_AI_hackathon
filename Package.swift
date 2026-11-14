// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .library(name: "FlowLLM", targets: ["FlowLLM"]),
        .executable(name: "FlowApp", targets: ["FlowApp"]),
    ],
    targets: [
        // Shared contracts: intents, typed actions, risk, errors. No I/O.
        .target(name: "FlowCore"),
        // Bonsai via LM Studio: HTTP client, prompt, schema, validation.
        .target(name: "FlowLLM", dependencies: ["FlowCore"]),
        // SwiftUI shell. Depends on FlowCore abstractions + FlowLLM provider.
        .executableTarget(name: "FlowApp", dependencies: ["FlowCore", "FlowLLM"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowLLMTests", dependencies: ["FlowCore", "FlowLLM"]),
    ]
)
