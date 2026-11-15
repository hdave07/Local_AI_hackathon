import FlowPlanner
import FlowSession
import SwiftUI

struct VoiceView: View {
    @Bindable var model: VoiceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if model.isListening {
                    Button("Stop listening") { Task { await model.stopListening() } }
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("Start listening") { Task { await model.startListening() } }
                        .disabled(!VoiceViewModel.speechAvailable)
                }
                ListenBadge(status: model.status.listen)
                Spacer()
                Label(model.mailScopeDescription, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.keySource == .none {
                HStack {
                    SecureField("Argmax runtime key (ax_…)", text: $model.keyEntry)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .accessibilityLabel("Argmax runtime key")
                    Button("Save to Keychain") { model.saveKey() }
                        .disabled(model.keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Needed for speech recognition. Stored only in your login Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = model.keyMessage { Text(message).font(.caption).foregroundStyle(.secondary) }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    if case .hearing(let words) = model.status.listen {
                        Text("Hearing: \(words)").foregroundStyle(.secondary).italic()
                    }
                    if let heard = model.lastHeard {
                        Text("You said: “\(heard)”").font(.title3).accessibilityLabel("Last heard: \(heard)")
                    }
                    TaskPhaseView(phase: model.status.task) { option in model.say(option) }
                    ForEach(model.lastReply, id: \.self) { line in
                        Text(line).accessibilityLabel("Flow: \(line)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                Text("Flow")
            }

            HStack {
                TextField("Or type what you'd say, e.g. “Open Notes”", text: $model.typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submitTyped() }
                    .accessibilityLabel("Typed command")
                Button("Send to Flow") { model.submitTyped() }
                    .disabled(model.typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                Section("Turns") {
                    ForEach(model.turns) { turn in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(turn.source == .voice ? "🎙" : "⌨︎") \(turn.utterance)  ·  \(Self.describe(turn.state))  ·  \(Self.ms(turn.duration)) ms")
                                .font(.callout.monospaced().bold())
                            if let plan = turn.planSummary { Text("plan: \(plan)").font(.caption.monospaced()) }
                            Text(turn.say.joined(separator: " ")).font(.caption)
                        }
                    }
                }
                Section("Executor") {
                    ForEach(Array(model.executorLog.enumerated()), id: \.offset) { _, e in
                        Text("\(e.action) → \(e.status.rawValue) · \(e.observation) · \(e.userMessage)")
                            .font(.caption.monospaced())
                    }
                }
            }

            Label("Sending, deleting and drafting are disabled. Only finalized speech is acted on; say “stop” to interrupt.",
                  systemImage: "hand.raised")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    static func describe(_ state: RunState) -> String {
        switch state {
        case .idle: "idle"
        case .running: "running"
        case .awaitingChoice: "asking"
        case .awaitingConfirmation: "confirming"
        case .completed: "completed"
        case .stopped: "stopped"
        case .cancelled: "cancelled"
        }
    }

    static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

private struct ListenBadge: View {
    let status: ListenStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(text).font(.callout)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch status {
        case .off: "Not listening"
        case .starting: "Starting…"
        case .listening: "Listening"
        case .hearing: "Hearing…"
        case .failed(let message): message
        }
    }

    private var color: Color {
        switch status {
        case .off: .gray
        case .starting: .yellow
        case .listening, .hearing: .green
        case .failed: .red
        }
    }
}

private struct TaskPhaseView: View {
    let phase: TaskPhase
    let choose: (String) -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working(let text):
            HStack { ProgressView().controlSize(.small); Text("Working on “\(text)”…") }
        case .awaitingChoice(let prompt, let options):
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt).bold()
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Button(option) { choose("number \(index + 1)") }
                        .buttonStyle(.link)
                        .accessibilityLabel("Choose \(index + 1): \(option)")
                }
            }
        case .awaitingConfirmation(let prompt), .awaitingAnswer(let prompt):
            Text(prompt).bold()
        case .finished:
            EmptyView()
        }
    }
}
