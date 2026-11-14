// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The Argmax Pro SDK comes from Argmax's authenticated Swift package registry.
// One-time setup per machine (token = SECRET_API_TOKEN, `axst_…`, never commit it):
//   swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
//   swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token <SECRET_API_TOKEN>
// Teammates without registry access can build everything else with FLOW_DISABLE_ARGMAX=1.
let argmaxEnabled = ProcessInfo.processInfo.environment["FLOW_DISABLE_ARGMAX"] != "1"

var products: [Product] = [
    .library(name: "FlowCore", targets: ["FlowCore"]),
    .library(name: "FlowLLM", targets: ["FlowLLM"]),
    .library(name: "FlowWindow", targets: ["FlowWindow"]),
    .library(name: "FlowAudio", targets: ["FlowAudio"]),
    .executable(name: "FlowApp", targets: ["FlowApp"]),
    .executable(name: "flowctl", targets: ["flowctl"]),
    .executable(name: "flow-bench", targets: ["FlowBenchCLI"]),
]

var targets: [Target] = [
    // Shared contracts: intents, typed actions, risk, errors, utterances. No I/O.
    .target(name: "FlowCore"),
    // Track B — Bonsai via LM Studio: HTTP client, prompt, schema, validation.
    .target(name: "FlowLLM", dependencies: ["FlowCore"]),
    // Track A — app launch/switch and window control via Accessibility.
    .target(name: "FlowWindow", dependencies: ["FlowCore"]),
    // Track B — speech pipeline contracts and logic, independent of any speech SDK:
    // microphone permission, utterance endpointing, VAD, control phrases, routing.
    .target(name: "FlowAudio", dependencies: ["FlowCore"]),
    // SwiftUI shell. Composition root for FlowLLM and FlowWindow.
    .executableTarget(name: "FlowApp", dependencies: ["FlowCore", "FlowLLM", "FlowWindow"]),
    // Typed command-line interface to FlowWindow for manual and scripted testing.
    .executableTarget(name: "flowctl", dependencies: ["FlowCore", "FlowWindow"]),
    // Track B — T-002 benchmark harness: fixtures → Bonsai via LM Studio → CSV + summary. Executes nothing.
    .executableTarget(name: "FlowBenchCLI", dependencies: ["FlowCore", "FlowLLM"]),
    .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    .testTarget(name: "FlowLLMTests", dependencies: ["FlowCore", "FlowLLM"]),
    .testTarget(name: "FlowWindowTests", dependencies: ["FlowCore", "FlowWindow"]),
    .testTarget(name: "FlowAudioTests", dependencies: ["FlowCore", "FlowAudio", "FlowLLM"]),
    .testTarget(name: "FlowBenchTests", dependencies: ["FlowBenchCLI", "FlowCore", "FlowLLM"]),
]

var dependencies: [Package.Dependency] = []

if argmaxEnabled {
    dependencies.append(.package(id: "argmaxinc.argmax-sdk-swift", exact: "3.1.8"))
    products.append(.library(name: "FlowArgmax", targets: ["FlowArgmax"]))
    products.append(.executable(name: "flow-voice", targets: ["FlowVoiceCLI"]))
    targets += [
        // Track B — Argmax Pro adapter implementing FlowAudio's `SpeechTranscribing`.
        .target(
            name: "FlowArgmax",
            dependencies: ["FlowAudio", .product(name: "Argmax", package: "argmaxinc.argmax-sdk-swift")]),
        // Track B developer harness: microphone/file → Argmax → Bonsai → mock consumer.
        // Executes nothing.
        .executableTarget(name: "FlowVoiceCLI", dependencies: ["FlowCore", "FlowAudio", "FlowArgmax", "FlowLLM"]),
        .testTarget(name: "FlowArgmaxTests", dependencies: ["FlowAudio", "FlowArgmax", "FlowCore", "FlowLLM"]),
    ]
}

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
