import FlowAudio
import FlowCalendar
import FlowExecutor
import FlowSession
import Foundation
import Observation
#if canImport(FlowArgmax)
import FlowArgmax
#endif

/// Voice tab: drives the `VoiceSessionCoordinator` and mirrors its events for SwiftUI.
@MainActor
@Observable
final class VoiceViewModel {
    var typed = ""
    var keyEntry = ""
    private(set) var status = CoordinatorStatus()
    private(set) var lastHeard: String?
    private(set) var lastReply: [String] = []
    private(set) var turns: [SessionTurn] = []
    private(set) var executorLog: [ExecutionLogEntry] = []
    private(set) var keySource: ArgmaxKeyStore.Source = .none
    private(set) var keyMessage: String?
    let mailScopeDescription: String

    private let coordinator: VoiceSessionCoordinator
    private let executor: MacPlanExecutor
    private var listener: Task<Void, Never>?

    init(coordinator: VoiceSessionCoordinator, executor: MacPlanExecutor) {
        self.coordinator = coordinator
        self.executor = executor
        let mail: String
        switch executor.configuration.mailScope {
        case .testMailbox(let name): mail = "Mail: \(name) mailbox only (test mode)"
        case .inbox: mail = "Mail: Inbox"
        }
        mailScopeDescription = mail + " · Calendar: " + (executor.calendarScope?.description ?? "off")
        keySource = ArgmaxKeyStore.load().source
        listener = Task { [weak self, coordinator] in
            for await event in coordinator.events { self?.apply(event) }
        }
    }

    static var speechAvailable: Bool {
        #if canImport(FlowArgmax)
        true
        #else
        false
        #endif
    }

    var isListening: Bool {
        switch status.listen {
        case .starting, .listening, .hearing: true
        default: false
        }
    }

    func startListening() async {
        let (key, source) = ArgmaxKeyStore.load()
        keySource = source
        #if canImport(FlowArgmax)
        if let key {
            var settings = ArgmaxSettings.fromEnvironment()
            settings.apiKey = key
            await coordinator.setTranscriber(ArgmaxTranscriber(settings: settings))
        }
        #endif
        await coordinator.startListening()
    }

    func stopListening() async {
        await coordinator.stopListening()
    }

    func submitTyped() {
        let text = typed
        typed = ""
        Task { await coordinator.submit(text) }
    }

    func say(_ text: String) {
        Task { await coordinator.submit(text) }
    }

    func saveKey() {
        if let problem = ArgmaxKeyStore.save(keyEntry) {
            keyMessage = "Couldn't save the key: \(problem)"
        } else {
            keyMessage = "Saved to your login Keychain."
            keySource = .keychain
        }
        keyEntry = ""
    }

    private func apply(_ event: CoordinatorEvent) {
        switch event {
        case .status(let s): status = s
        case .finalized(let text): lastHeard = text
        case .incomplete: break
        case .turn(let turn):
            turns.insert(turn, at: 0)
            if turns.count > 50 { turns.removeLast() }
            lastReply = turn.say
            executorLog = Array(executor.log.suffix(20).reversed())
        }
    }
}
