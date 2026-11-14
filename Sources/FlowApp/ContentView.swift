import FlowCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: ClassifierViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServerStatusView(status: model.serverStatus) {
                Task { await model.checkServer() }
            }

            HStack {
                TextField("Type a command, e.g. “open notes”", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit { model.submit() }
                    .accessibilityLabel("Command")
                if model.isBusy {
                    Button("Cancel", role: .cancel) { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Interpret") { model.submit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            ResultView(phase: model.phase)

            Spacer(minLength: 0)

            Label("Preview only — Flow does not perform any action yet.", systemImage: "eye")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
        .task {
            fieldFocused = true
            await model.checkServer()
        }
    }
}

private struct ServerStatusView: View {
    let status: ClassifierViewModel.ServerStatus
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(text).font(.callout)
            Spacer()
            Button("Recheck", action: retry).controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .checking: .gray
        case .ready: .green
        case .modelNotLoaded: .orange
        case .unavailable: .red
        }
    }

    private var text: String {
        switch status {
        case .checking: "Checking LM Studio…"
        case .ready(let id): "LM Studio (local) · \(id)"
        case .modelNotLoaded(let id, _): "LM Studio is running, but \(id) isn't loaded."
        case .unavailable(let message): message
        }
    }
}

private struct ResultView: View {
    let phase: ClassifierViewModel.Phase

    var body: some View {
        GroupBox {
            Group {
                switch phase {
                case .idle:
                    Text("The interpreted action will appear here.")
                        .foregroundStyle(.secondary)
                case .classifying:
                    HStack { ProgressView().controlSize(.small); Text("Interpreting…") }
                case .interpreted(let intent, let latency):
                    IntentDetails(intent: intent, latency: latency)
                case .failed(let error):
                    Label(error.userMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(error == .cancelled ? Color.secondary : Color.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Text("Interpretation")
        }
    }
}

private struct IntentDetails: View {
    let intent: Intent
    let latency: Duration

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Action", intent.action?.type.rawValue ?? intent.control?.rawValue ?? "none")
            row("Target", intent.action?.targetDescription ?? "—")
            row("Kind", intent.kind.rawValue)
            row("Risk", intent.risk.rawValue)
            row("Summary", intent.summary)
            row("Source", source)
        }
        .textSelection(.enabled)
    }

    private var source: String {
        let ms = Int(latency.components.seconds * 1000)
            + Int(latency.components.attoseconds / 1_000_000_000_000_000)
        switch intent.source {
        case .deterministic: return "Deterministic router · \(ms) ms"
        case .model(let id): return "\(id) · \(ms) ms"
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value).font(name == "Action" ? .title3.monospaced() : .body)
        }
    }
}
