import AppKit
import FlowCore
import FlowLLM
import SwiftUI

@main
struct FlowApp: App {
    @State private var model: ClassifierViewModel

    init() {
        // Composition root. Defaults match the verified local setup; the
        // FLOW_LMSTUDIO_URL / FLOW_MODEL_ID environment variables override them.
        let env = ProcessInfo.processInfo.environment
        let baseURL = env["FLOW_LMSTUDIO_URL"].flatMap(URL.init(string:)) ?? LMStudioConfiguration.defaultBaseURL
        let modelID = env["FLOW_MODEL_ID"] ?? LMStudioConfiguration.defaultModelID

        let configuration: LMStudioConfiguration
        do {
            configuration = try LMStudioConfiguration(baseURL: baseURL, modelID: modelID)
        } catch {
            // Refuse non-local overrides rather than silently falling back to a remote server.
            fatalError("Invalid Flow model configuration: \(error.userMessage)")
        }
        let client = LMStudioClient(configuration: configuration)
        _model = State(initialValue: ClassifierViewModel(
            classifier: BonsaiIntentClassifier(client: client),
            modelID: configuration.modelID,
            listModels: { () async throws(ClassificationError) -> [String] in try await client.listModels() }
        ))
    }

    var body: some Scene {
        WindowGroup("Flow") {
            ContentView(model: model)
                .onAppear {
                    // Needed when launched as a bare SwiftPM executable (no .app bundle).
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
