// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .library(name: "FlowLLM", targets: ["FlowLLM"]),
        .library(name: "FlowWindow", targets: ["FlowWindow"]),
        .executable(name: "FlowApp", targets: ["FlowApp"]),
        .executable(name: "flowctl", targets: ["flowctl"]),
    ],
    targets: [
        // Shared contracts: intents, typed actions, risk, errors. No I/O.
        .target(name: "FlowCore"),
        // Track B — Bonsai via LM Studio: HTTP client, prompt, schema, validation.
        .target(name: "FlowLLM", dependencies: ["FlowCore"]),
        // Track A — app launch/switch and window control via Accessibility.
        .target(name: "FlowWindow", dependencies: ["FlowCore"]),
        // SwiftUI shell. Composition root for FlowLLM and FlowWindow.
        .executableTarget(name: "FlowApp", dependencies: ["FlowCore", "FlowLLM", "FlowWindow"]),
        // Typed command-line interface to FlowWindow for manual and scripted testing.
        .executableTarget(name: "flowctl", dependencies: ["FlowCore", "FlowWindow"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowLLMTests", dependencies: ["FlowCore", "FlowLLM"]),
        .testTarget(name: "FlowWindowTests", dependencies: ["FlowCore", "FlowWindow"]),
    ]
)
