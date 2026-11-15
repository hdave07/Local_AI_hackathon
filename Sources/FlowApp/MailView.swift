import FlowAX
import FlowMail
import SwiftUI

struct MailView: View {
    @Bindable var model: MailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.statusLine, systemImage: "envelope")
                    .font(.callout)
                Spacer()
                Button("Check Mail") { Task { await model.checkStatus(request: false) } }
                Button("Allow Mail access") { Task { await model.checkStatus(request: true) } }
                    .help("Shows macOS's Automation prompt if Flow hasn't been allowed to use Mail yet.")
            }
            .controlSize(.small)

            HStack {
                TextField("Mail command, e.g. “find mail from Sarah”", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospaced())
                    .onSubmit { model.submit() }
                    .accessibilityLabel("Mail command")
                Button("Run") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.command.trimmingCharacters(in: .whitespaces).isEmpty)
                if model.isRunning { ProgressView().controlSize(.small) }
            }

            if !model.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matching messages").font(.headline)
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, message in
                        Button("\(index + 1). \(message.displayLine)") { Task { await model.run("choose \(index + 1)") } }
                            .buttonStyle(.link)
                            .accessibilityLabel("Choose \(index + 1): \(message.displayLine)")
                    }
                }
            }

            if let reading = model.reading {
                GroupBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reading.summary.subject).font(.headline)
                            Text("From \(reading.summary.sender)").font(.caption).foregroundStyle(.secondary)
                            Text(reading.body + (reading.truncated ? "\n[truncated]" : ""))
                                .textSelection(.enabled)
                                .accessibilityLabel("Message body")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                } label: {
                    Text("Reading")
                }
            }

            Text(MailCommandParser.usage).font(.caption).foregroundStyle(.secondary)

            List(model.log) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("> \(entry.input)").font(.callout.monospaced().bold())
                        if let status = entry.status {
                            Text(status.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(color(status).opacity(0.2), in: Capsule())
                                .foregroundStyle(color(status))
                        }
                    }
                    Text(entry.text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }

            Label("Read-only: Flow never sends, deletes, moves or flags messages. Typed commands only; the classifier is not connected.",
                  systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func color(_ status: NavigationStatus) -> Color {
        switch status {
        case .completed: .green
        case .needsClarification: .blue
        case .partiallyCompleted, .unverified: .orange
        case .failed: .red
        case .unsupported: .secondary
        }
    }
}
