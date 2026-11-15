import AppKit
import FlowAudio
import FlowAX
import FlowCalendar
import FlowCore
import FlowExecutor
import FlowHUD
import FlowLLM
import FlowMail
import FlowMailSend
import FlowPlanner
import FlowRouting
import FlowSession
import FlowSpeech
import FlowWindow
import SwiftUI

@main
struct FlowApp: App {
    @State private var model: ClassifierViewModel
    @State private var windowModel: WindowControlViewModel
    @State private var navigationModel: NavigationViewModel
    @State private var mailModel: MailViewModel
    @State private var voiceModel: VoiceViewModel
    @State private var hudController: HUDPanelController?
    @State private var menuBarMascot: MenuBarMascotController?

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
            // Confirmed sending (T-023C), off by default. FLOW_SEND_MODE=dry-run runs every check and
            // records the send without pressing Send. FLOW_SEND_MODE=live additionally requires
            // FLOW_SEND_ALLOWED_RECIPIENTS (comma-separated addresses); without it sending stays off.
            sender: Self.makeSender(env: env),
            configuration: ExecutorConfiguration(mailScope: .testMailbox("FlowTest")))
        let session = TaskSession(store: IntentRouter(model: BonsaiIntentClassifier(client: client)), executor: executor)
        let coordinator = VoiceSessionCoordinator(session: session, transcriber: nil, permission: SystemMicrophonePermission())

        // Floating HUD (ADR 0011): fed by the same coordinator events as the Voice tab, and by
        // spoken-feedback events. FLOW_HUD=off disables it.
        let hud: HUDModel? = env["FLOW_HUD"]?.lowercased() == "off" ? nil : HUDModel()
        // Spoken feedback (ADR 0008 decision 3): speaks questions, confirmations and failures;
        // drops Flow's own speech picked up by the microphone. FLOW_SPOKEN_FEEDBACK=off disables it.
        let feedback: SpokenFeedback? = env["FLOW_SPOKEN_FEEDBACK"]?.lowercased() == "off"
            ? nil : SpokenFeedback(output: SystemSpeechOutput())
        let voice = VoiceViewModel(coordinator: coordinator, executor: executor, hud: hud, feedback: feedback)
        _voiceModel = State(initialValue: voice)
        if let hud {
            hud.onToggleListening = { [weak voice] in
                guard let voice else { return }
                Task { voice.isListening ? await voice.stopListening() : await voice.startListening() }
            }
            hud.onSubmit = { [weak voice] text in voice?.say(text) }
            hud.onStopSpeaking = { Task { await feedback?.stopSpeaking() } }
            _hudController = State(initialValue: HUDPanelController(model: hud))
        }

        _model = State(initialValue: ClassifierViewModel(
            classifier: BonsaiIntentClassifier(client: client),
            modelID: configuration.modelID,
            listModels: { () async throws(ClassificationError) -> [String] in try await client.listModels() }
        ))
    }

    /// Sending is disabled unless explicitly configured; live sending needs a recipient allowlist.
    @MainActor
    static func makeSender(env: [String: String]) -> MailSender? {
        switch env["FLOW_SEND_MODE"]?.lowercased() {
        case "dry-run", "dryrun", "dry_run":
            return MailSender(mode: .dryRun, transport: JXAMailSendTransport())
        case "live":
            let allow = Set((env["FLOW_SEND_ALLOWED_RECIPIENTS"] ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
            guard !allow.isEmpty else { return nil }
            return MailSender(mode: .live, transport: JXAMailSendTransport(), configuration: .init(recipientAllowlist: allow))
        default:
            return nil
        }
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
                    hudController?.install()
                    if menuBarMascot == nil, let hud = hudController?.model {
                        menuBarMascot = MenuBarMascotController(model: hud)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("HUD") {
                Button("Show Flow HUD") { hudController?.model.show() }.keyboardShortcut("h", modifiers: [.command, .option])
                Button("Hide Flow HUD") { hudController?.model.hide() }
            }
        }
    }
}
