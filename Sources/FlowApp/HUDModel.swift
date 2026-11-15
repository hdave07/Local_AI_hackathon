import FlowHUD
import FlowSession
import FlowSpeech
import Foundation
import Observation

/// Observable wrapper around `HUDState` for SwiftUI, plus the HUD's few controls. All
/// controls go through the existing session API (`submit`, `startListening`, …); the HUD
/// never answers a confirmation and keeps no task context of its own.
@MainActor
@Observable
final class HUDModel {
    private(set) var state = HUDState()
    /// Accessible text size (1.0, 1.25, 1.5); remembered per Mac.
    var textScale: Double {
        didSet { UserDefaults.standard.set(textScale, forKey: Self.scaleKey); layoutChanged?() }
    }

    @ObservationIgnored var onToggleListening: (() -> Void)?
    @ObservationIgnored var onSubmit: ((String) -> Void)?
    @ObservationIgnored var onStopSpeaking: (() -> Void)?
    /// Called whenever the HUD's size may have changed (the panel re-fits and re-clamps).
    @ObservationIgnored var layoutChanged: (() -> Void)?
    @ObservationIgnored var visibilityChanged: ((Bool) -> Void)?

    static let scaleKey = "FlowHUD.textScale"

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.scaleKey)
        textScale = [1.0, 1.25, 1.5].contains(saved) ? saved : 1.0
    }

    func apply(_ input: HUDState.Input) {
        let wasHidden = state.hidden
        state.apply(input)
        if state.hidden != wasHidden { visibilityChanged?(!state.hidden) }
        layoutChanged?()
    }

    // MARK: Controls

    func toggleListening() { onToggleListening?() }
    func setCollapsed(_ on: Bool) { apply(.setCollapsed(on)) }
    func hide() { apply(.setHidden(true)) }
    func show() { apply(.setHidden(false)) }
    func stopSpeaking() { onStopSpeaking?() }
    /// Picks a numbered choice exactly as if it were said ("2"); never used for confirmations.
    func choose(_ number: Int) {
        guard !state.isConfirmation, state.choices.contains(where: { $0.number == number }) else { return }
        onSubmit?("\(number)")
    }
    /// Declining is always safe; approving a send is only possible by saying "yes".
    func declineConfirmation() {
        guard state.isConfirmation else { return }
        onSubmit?("no")
    }
    func cancelQuestion() {
        guard state.expectsResponse else { return }
        onSubmit?("cancel")
    }
    func cycleTextScale() {
        textScale = textScale >= 1.5 ? 1.0 : textScale + 0.25
    }
}
