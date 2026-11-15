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
    .library(name: "FlowRouting", targets: ["FlowRouting"]),
    .executable(name: "FlowApp", targets: ["FlowApp"]),
    .executable(name: "flowctl", targets: ["flowctl"]),
    .executable(name: "flow-bench", targets: ["FlowBenchCLI"]),
    .library(name: "FlowAX", targets: ["FlowAX"]),
    .executable(name: "flow-nav-fixture", targets: ["FlowNavFixture"]),
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
    // Track A — generic UI navigation: AX inspection, deterministic target resolution,
    // revalidated press/focus/select/scroll with verification, numbered overlay.
    .target(name: "FlowAX", dependencies: ["FlowCore", "FlowWindow"]),
    // Track A — deterministic AppKit app exercised by FlowAX live integration tests.
    .executableTarget(name: "FlowNavFixture"),
    // Track B — intent router: control phrases, fast path, task context and references,
    // clarification, Bonsai fallback with slot grounding. Proposes intents; executes nothing.
    .target(name: "FlowRouting", dependencies: ["FlowCore", "FlowLLM"]),
    // SwiftUI shell. Composition root for FlowLLM, FlowWindow and FlowAX.
    .executableTarget(name: "FlowApp", dependencies: ["FlowCore", "FlowLLM", "FlowWindow", "FlowAX"]),
    // Typed command-line interface to FlowWindow and FlowAX for manual and scripted testing.
    .executableTarget(name: "flowctl", dependencies: ["FlowCore", "FlowWindow", "FlowAX"]),
    // Track B — T-002 benchmark harness: fixtures → Bonsai via LM Studio → CSV + summary. Executes nothing.
    .executableTarget(name: "FlowBenchCLI", dependencies: ["FlowCore", "FlowLLM", "FlowRouting"]),
    .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    .testTarget(name: "FlowLLMTests", dependencies: ["FlowCore", "FlowLLM"]),
    .testTarget(name: "FlowWindowTests", dependencies: ["FlowCore", "FlowWindow"]),
    .testTarget(name: "FlowAXTests", dependencies: ["FlowCore", "FlowWindow", "FlowAX"]),
    .testTarget(name: "FlowAudioTests", dependencies: ["FlowCore", "FlowAudio", "FlowLLM"]),
    .testTarget(name: "FlowBenchTests", dependencies: ["FlowBenchCLI", "FlowCore", "FlowLLM"]),
    .testTarget(name: "FlowRoutingTests", dependencies: ["FlowRouting", "FlowCore", "FlowLLM"]),
]

var dependencies: [Package.Dependency] = []

if argmaxEnabled {
    dependencies.append(.package(id: "argmaxinc.argmax-sdk-swift", exact: "3.1.8"))
    products.append(.library(name: "FlowArgmax", targets: ["FlowArgmax"]))
    products.append(.executable(name: "flow-voice", targets: ["FlowVoiceCLI"]))
    products.append(.executable(name: "flow-speech-eval", targets: ["FlowSpeechEvalCLI"]))
    targets += [
        // Track B — Argmax Pro adapter implementing FlowAudio's `SpeechTranscribing`.
        .target(
            name: "FlowArgmax",
            dependencies: ["FlowAudio", .product(name: "Argmax", package: "argmaxinc.argmax-sdk-swift")]),
        // Track B developer harness: microphone/file → Argmax → Bonsai → mock consumer.
        // Executes nothing.
        .executableTarget(name: "FlowVoiceCLI", dependencies: ["FlowCore", "FlowAudio", "FlowArgmax", "FlowLLM", "FlowRouting"]),
        // Track B speech robustness/segmentation harness (synthesized speech → Argmax). Executes nothing.
        .executableTarget(name: "FlowSpeechEvalCLI", dependencies: ["FlowAudio", "FlowArgmax"]),
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
