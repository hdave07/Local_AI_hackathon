import AppKit
import FlowAudio
import FlowAX
import FlowCalendar
import FlowCore
import FlowExecutor
import FlowLLM
import FlowMail
import FlowPlanner
import FlowRouting
import FlowSession
import FlowWindow
import SwiftUI

@main
struct FlowApp: App {
    @State private var model: ClassifierViewModel
    @State private var windowModel: WindowControlViewModel
    @State private var navigationModel: NavigationViewModel
    @State private var mailModel: MailViewModel
    @State private var voiceModel: VoiceViewModel

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

        // Voice → TaskSession (router + planner) → real executor. The executor has its own
        // controllers (separate undo history and numbered sets from the typed tabs), shares the
        // frontmost-app tracker, and is restricted to the synthetic FlowTest mailbox.
        let executorMail = JXAMailBackend()
        var executorNavigation = UINavigator.Configuration()
        executorNavigation.bringTargetToFront = true
        let executor = MacPlanExecutor(
            window: WindowController(backend: windowBackend),
            navigator: UINavigator(backend: AXUIBackend(frontmost: { windowBackend.frontmostApp() }),
                                   overlay: ScreenOverlay(), configuration: executorNavigation),
            mail: MailController(backend: executorMail, verifier: AXMailDisplayVerifier()),
            // Reply drafts (T-023A): created, verified on screen and shown for review; never sent.
            drafts: MailDraftController(mail: executorMail, backend: executorMail, inspector: AXMailComposeInspector()),
            // Read-only calendar (T-024). Development scope is the FlowTest calendar; FLOW_CALENDAR_SCOPE=all
            // reads every calendar the user has authorized. Answers always name the calendars checked.
            calendar: CalendarController(store: EventKitStore(),
                                         scope: env["FLOW_CALENDAR_SCOPE"] == "all" ? .allAuthorized : .named(["FlowTest"]),
                                         viewer: JXACalendarViewer()),
            configuration: ExecutorConfiguration(mailScope: .testMailbox("FlowTest")))
        let session = TaskSession(store: IntentRouter(model: BonsaiIntentClassifier(client: client)), executor: executor)
        let coordinator = VoiceSessionCoordinator(session: session, transcriber: nil, permission: SystemMicrophonePermission())
        _voiceModel = State(initialValue: VoiceViewModel(coordinator: coordinator, executor: executor))

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
                VoiceView(model: voiceModel)
                    .tabItem { Label("Voice", systemImage: "mic") }
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
