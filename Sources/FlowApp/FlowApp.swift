import AppKit
import FlowAX
import FlowCore
import FlowLLM
import FlowMail
import FlowWindow
import SwiftUI

@main
struct FlowApp: App {
    @State private var model: ClassifierViewModel
    @State private var windowModel: WindowControlViewModel
    @State private var navigationModel: NavigationViewModel
    @State private var mailModel: MailViewModel

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
        // One frontmost-app tracker shared by window control and UI navigation, so "the
        // frontmost app" means the app used before clicking into Flow.
        let windowBackend = AXWindowBackend()
        _windowModel = State(initialValue: WindowControlViewModel(controller: WindowController(backend: windowBackend)))
        var navigation = UINavigator.Configuration()
        navigation.bringTargetToFront = true  // commands are typed into Flow, which is then frontmost
        _navigationModel = State(initialValue: NavigationViewModel(navigator: UINavigator(
            backend: AXUIBackend(frontmost: { windowBackend.frontmostApp() }),
            overlay: ScreenOverlay(),
            configuration: navigation)))

        _mailModel = State(initialValue: MailViewModel(controller: MailController(
            backend: JXAMailBackend(), verifier: AXMailDisplayVerifier())))

        let client = LMStudioClient(configuration: configuration)
        _model = State(initialValue: ClassifierViewModel(
            classifier: BonsaiIntentClassifier(client: client),
            modelID: configuration.modelID,
            listModels: { () async throws(ClassificationError) -> [String] in try await client.listModels() }
        ))
    }

    var body: some Scene {
        WindowGroup("Flow") {
            TabView {
                ContentView(model: model)
                    .tabItem { Label("Interpret", systemImage: "text.bubble") }
                WindowControlView(model: windowModel)
                    .tabItem { Label("Window Control", systemImage: "macwindow") }
                NavigationView(model: navigationModel)
                    .tabItem { Label("UI Navigation", systemImage: "cursorarrow.click") }
                MailView(model: mailModel)
                    .tabItem { Label("Mail", systemImage: "envelope") }
            }
                .onAppear {
                    // Needed when launched as a bare SwiftPM executable (no .app bundle).
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
