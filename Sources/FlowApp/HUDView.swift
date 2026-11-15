import FlowHUD
import SwiftUI

/// The floating HUD's content, in the Flow design: the onigiri mascot, frosted panels,
/// rounded type, one blush accent. State is still shown with words and symbols, never by
/// color alone, and the "what to say next" hint lives in the tooltip and VoiceOver hint.
struct HUDView: View {
    @Bindable var model: HUDModel
    /// A just-finished outcome, shown on the mascot's face for a few seconds.
    @State private var flash: HUDOutcomeKind?
    @State private var flashToken = UUID()

    private var s: HUDState { model.state }
    private var mood: MascotMood { MascotMood(activity: s.activity, flash: flash) }
    private func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        FlowTheme.font(size, weight, scale: model.textScale)
    }

    var body: some View {
        Group {
            if s.collapsed { collapsed } else { expanded }
        }
        .foregroundStyle(FlowTheme.ink)
        .tint(FlowTheme.ink)
        .fixedSize()
        .padding(FlowTheme.shadowRoom)  // room for the soft shadow
        .onChange(of: s.outcome) { _, new in showFlash(for: new) }
    }

    private func showFlash(for outcome: HUDOutcome?) {
        guard let kind = outcome?.kind, kind == .verified || kind == .notDone else { return }
        flash = kind
        let token = UUID()
        flashToken = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if flashToken == token { flash = nil }
        }
    }

    // MARK: Collapsed: a small pill that still shows listening/speaking and pending questions.

    private var collapsed: some View {
        HStack(spacing: 8) {
            OnigiriMascot(mood: mood, floating: false)
                .frame(width: 30 * model.textScale, height: 28 * model.textScale)
            Text(s.activity.label).font(font(13, .bold)).lineLimit(1)
            if s.expectsResponse {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(FlowTheme.blush)
                    .accessibilityLabel("Flow is waiting for your answer")
            }
            iconButton(s.listening ? "stop.circle.fill" : "mic.fill", help: s.listening ? "Stop listening" : "Start listening",
                       label: s.listening ? "Stop listening" : "Start listening") { model.toggleListening() }
            iconButton("chevron.down", help: "Expand", label: "Expand the Flow HUD") { model.setCollapsed(false) }
        }
        .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
        .flowGlass(Capsule(), emphasized: s.expectsResponse)
        .help(s.hint)
        .accessibilityHint(s.hint)
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = s.errorMessage {
                symbolRow("exclamationmark.octagon.fill", label: "Error") {
                    Text(error).font(font(12)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let question = s.question { questionBlock(question) }
            if let outcome = s.outcome, !s.expectsResponse { outcomeRow(outcome) }
            if let speaking = s.speaking {
                symbolRow("speaker.wave.2.fill", label: "Flow is saying") {
                    Text(speaking).font(font(12)).foregroundStyle(FlowTheme.inkSecondary).lineLimit(3)
                    Spacer(minLength: 0)
                    softButton("Stop speaking") { model.stopSpeaking() }
                }
            }
            if let note = s.voiceNote {
                Text(note).font(font(11)).foregroundStyle(FlowTheme.inkSecondary)
            }
            if let ignored = s.ignored {
                Text("Ignored while Flow was speaking: “\(ignored)”").font(font(11))
                    .foregroundStyle(FlowTheme.inkSecondary).lineLimit(2)
            }
            // Visible, not only a tooltip: Flow's users may not be able to hover with a pointer.
            // During a send confirmation the question block already says how to send.
            if !s.isConfirmation {
                Text(s.hint).font(font(11)).foregroundStyle(FlowTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !s.recent.isEmpty, !s.expectsResponse { recent }
        }
        .padding(14)
        .frame(width: 320 * min(model.textScale, 1.3), alignment: .leading)
        .flowGlass(RoundedRectangle(cornerRadius: FlowTheme.cardRadius, style: .continuous), emphasized: s.expectsResponse)
        .help(s.hint)
        .accessibilityHint(s.hint)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            OnigiriMascot(mood: mood).frame(width: 48, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.activity.label).font(font(14, .bold))
                heard
            }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                iconButton(s.listening ? "stop.circle.fill" : "mic.fill",
                           help: s.listening ? "Stop listening (or say “stop”)" : "Start listening",
                           label: s.listening ? "Stop listening" : "Start listening") { model.toggleListening() }
                iconButton("textformat.size", help: "Text size", label: "Change text size") { model.cycleTextScale() }
                iconButton("chevron.up", help: "Collapse", label: "Collapse the Flow HUD") { model.setCollapsed(true) }
                iconButton("xmark", help: "Hide the HUD (your task keeps going)",
                           label: "Hide the Flow HUD. Your task keeps going.") { model.hide() }
                Menu {
                    Button("Show Flow window") { model.showMainWindow() }
                    Divider()
                    Button("Quit Flow") { model.quit() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("More").accessibilityLabel("More: show Flow window, quit Flow")
            }
        }
    }

    @ViewBuilder private var heard: some View {
        if let hearing = s.hearing {
            Text("\(hearing)…").font(font(12)).foregroundStyle(FlowTheme.inkSecondary).lineLimit(2)
        } else if let last = s.lastHeard {
            Text("“\(last)”").font(font(12)).foregroundStyle(FlowTheme.inkSecondary).lineLimit(2)
                .accessibilityLabel("You said: \(last)")
        }
    }

    private func questionBlock(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question).font(font(15, .bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(s.choices) { choice in
                Button { model.choose(choice.number) } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(choice.number)").font(font(13, .heavy))
                            .frame(width: 24 * model.textScale, height: 24 * model.textScale)
                            .background(FlowTheme.blush.opacity(0.22), in: Circle())
                        Text(choice.text).font(font(13)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FlowTheme.panelEdge))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choice \(choice.number): \(choice.text)")
            }
            HStack(spacing: 8) {
                if s.isConfirmation {
                    // No "send" button: a send needs a spoken, explicit yes (ADR 0010).
                    // This one line stays visible because there is nothing to click to send.
                    Text("Say “yes, send it” to send.").font(font(11)).foregroundStyle(FlowTheme.inkSecondary)
                    Spacer(minLength: 0)
                    softButton("No, don't send") { model.declineConfirmation() }
                } else {
                    Spacer(minLength: 0)
                    softButton("Cancel") { model.cancelQuestion() }
                }
            }
        }
    }

    private func outcomeRow(_ outcome: HUDOutcome) -> some View {
        let (symbol, prefix): (String, String) = switch outcome.kind {
        case .verified: ("checkmark.circle.fill", "Done")
        case .notDone: ("exclamationmark.triangle.fill", "Not done")
        case .cancelled: ("xmark.circle.fill", "Stopped")
        case .info: ("info.circle.fill", "Note")
        }
        return symbolRow(symbol, label: prefix) {
            Text(outcome.text).font(font(12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recent: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(s.recent) { e in
                    Text("“\(e.heard)” — \(e.summary)").font(font(11)).foregroundStyle(FlowTheme.inkSecondary).lineLimit(2)
                }
            }
        } label: {
            Text("Recent").font(font(11, .semibold)).foregroundStyle(FlowTheme.inkSecondary)
        }
    }

    // MARK: Building blocks

    /// A blush SF Symbol (shape carries meaning) followed by content.
    private func symbolRow<Content: View>(_ symbol: String, label: String,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(font(13, .semibold)).foregroundStyle(FlowTheme.blush)
                .accessibilityLabel(label)
            content()
        }
    }

    private func iconButton(_ symbol: String, help: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(font(11, .bold)).foregroundStyle(FlowTheme.inkSecondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(label)
    }

    private func softButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(font(12, .semibold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.white.opacity(0.65), in: Capsule())
                .overlay(Capsule().strokeBorder(FlowTheme.panelEdge))
        }
        .buttonStyle(.plain)
    }
}

/// Kept for anything else that still uses it; the HUD itself now shows the mascot.
struct StatusDot: View {
    let activity: HUDActivity

    var body: some View {
        let symbol: String = switch activity {
        case .idle: "mic.slash"
        case .listening: "mic.fill"
        case .hearing: "waveform"
        case .processing: "gearshape.fill"
        case .speaking: "speaker.wave.2.fill"
        case .awaitingChoice, .awaitingAnswer: "questionmark.circle.fill"
        case .awaitingConfirmation: "hand.raised.fill"
        case .error: "exclamationmark.octagon.fill"
        }
        Image(systemName: symbol).foregroundStyle(FlowTheme.blush).font(.system(size: 14, weight: .semibold))
            .frame(width: 18).accessibilityHidden(true)
    }
}
