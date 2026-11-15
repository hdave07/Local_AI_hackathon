import FlowHUD
import SwiftUI

/// The floating HUD's content. State is shown with words and symbols, never by color alone.
struct HUDView: View {
    @Bindable var model: HUDModel

    private var s: HUDState { model.state }
    private func font(_ size: Double, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * model.textScale, weight: weight)
    }

    var body: some View {
        Group {
            if s.collapsed { collapsed } else { expanded }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(s.expectsResponse ? Color.orange : Color.secondary.opacity(0.25), lineWidth: s.expectsResponse ? 2 : 1))
        .fixedSize()
    }

    // MARK: Collapsed: a status pill that still shows listening/speaking and pending questions.

    private var collapsed: some View {
        HStack(spacing: 8) {
            StatusDot(activity: s.activity)
            Text(s.activity.label).font(font(12, .medium)).lineLimit(1)
            if s.expectsResponse {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                    .accessibilityLabel("Flow is waiting for your answer")
            }
            Button { model.setCollapsed(false) } label: { Image(systemName: "chevron.down.circle") }
                .buttonStyle(.borderless).help("Expand").accessibilityLabel("Expand the Flow HUD")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let error = s.errorMessage {
                Label(error, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).font(font(12))
            }
            if s.expectsResponse {
                Text("Flow is waiting for you").font(font(11, .semibold)).foregroundStyle(.orange)
                    .accessibilityAddTraits(.isHeader)
            }
            heard
            if let question = s.question { questionBlock(question) }
            if let outcome = s.outcome, !s.expectsResponse { outcomeRow(outcome) }
            if let speaking = s.speaking {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.purple)
                    Text(speaking).font(font(11)).foregroundStyle(.secondary).lineLimit(3)
                    Spacer(minLength: 0)
                    Button("Stop speaking") { model.stopSpeaking() }.controlSize(.small)
                }
            }
            if let note = s.voiceNote { Text(note).font(font(10)).foregroundStyle(.secondary) }
            if let ignored = s.ignored {
                Text("Ignored while Flow was speaking: “\(ignored)”").font(font(10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(s.hint).font(font(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !s.recent.isEmpty, !s.expectsResponse { recent }
        }
        .padding(12)
        .frame(width: 340 * min(model.textScale, 1.3), alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(activity: s.activity)
            Text(s.activity.label).font(font(13, .semibold))
            Spacer(minLength: 4)
            Button { model.toggleListening() } label: {
                Image(systemName: s.listening ? "mic.slash.fill" : "mic.fill")
            }
            .buttonStyle(.borderless).help(s.listening ? "Stop listening" : "Start listening")
            .accessibilityLabel(s.listening ? "Stop listening" : "Start listening")
            Button { model.cycleTextScale() } label: { Image(systemName: "textformat.size") }
                .buttonStyle(.borderless).help("Text size").accessibilityLabel("Change text size")
            Button { model.setCollapsed(true) } label: { Image(systemName: "chevron.up.circle") }
                .buttonStyle(.borderless).help("Collapse").accessibilityLabel("Collapse the Flow HUD")
            Button { model.hide() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("Hide the HUD (your task keeps going)")
                .accessibilityLabel("Hide the Flow HUD. Your task keeps going.")
        }
    }

    @ViewBuilder private var heard: some View {
        if let hearing = s.hearing {
            Text("“\(hearing)…”").font(font(12)).italic().foregroundStyle(.secondary).lineLimit(2)
        } else if let last = s.lastHeard {
            (Text("You said: ").foregroundStyle(.secondary) + Text("“\(last)”"))
                .font(font(12)).lineLimit(3)
        }
    }

    private func questionBlock(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question).font(font(13, .semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(s.choices) { choice in
                Button { model.choose(choice.number) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(choice.number)").font(font(13, .bold)).frame(minWidth: 18)
                        Text(choice.text).font(font(12)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Choice \(choice.number): \(choice.text)")
            }
            HStack {
                if s.isConfirmation {
                    // No "send" button: a send needs a spoken, explicit yes (ADR 0010).
                    Button("No, don't send") { model.declineConfirmation() }.controlSize(.small)
                } else {
                    Button("Cancel") { model.cancelQuestion() }.controlSize(.small)
                }
            }
        }
    }

    private func outcomeRow(_ outcome: HUDOutcome) -> some View {
        let (symbol, color, prefix): (String, Color, String) = switch outcome.kind {
        case .verified: ("checkmark.circle.fill", .green, "Done")
        case .notDone: ("exclamationmark.triangle.fill", .orange, "Not done")
        case .cancelled: ("xmark.circle.fill", .secondary, "Stopped")
        case .info: ("info.circle.fill", .blue, "Note")
        }
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityLabel(prefix)
            Text(outcome.text).font(font(12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recent: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(s.recent) { e in
                    Text("“\(e.heard)” — \(e.summary)").font(font(10)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } label: {
            Text("Recent").font(font(11))
        }
    }
}

/// A status symbol whose shape and color both change with the activity.
struct StatusDot: View {
    let activity: HUDActivity

    var body: some View {
        let (symbol, color): (String, Color) = switch activity {
        case .idle: ("mic.slash", .secondary)
        case .listening: ("mic.fill", .green)
        case .hearing: ("waveform", .green)
        case .processing: ("gearshape.fill", .blue)
        case .speaking: ("speaker.wave.2.fill", .purple)
        case .awaitingChoice, .awaitingAnswer: ("questionmark.circle.fill", .orange)
        case .awaitingConfirmation: ("hand.raised.fill", .orange)
        case .error: ("exclamationmark.octagon.fill", .red)
        }
        Image(systemName: symbol).foregroundStyle(color).font(.system(size: 14, weight: .semibold))
            .frame(width: 18).accessibilityHidden(true)
    }
}
