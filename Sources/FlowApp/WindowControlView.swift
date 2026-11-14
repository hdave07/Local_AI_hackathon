import AppKit
import FlowWindow
import SwiftUI

struct WindowControlView: View {
    @Bindable var model: WindowControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isTrusted {
                Label("Accessibility permission granted", systemImage: "checkmark.shield")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                PermissionBanner(model: model)
            }

            HStack {
                TextField("Window command, e.g. “move notes left_half”", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospaced())
                    .onSubmit { model.submit() }
                    .accessibilityLabel("Window command")
                Button("Run") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                ForEach(["activate notes", "move notes left_half", "list notes"], id: \.self) { text in
                    Button(text) { Task { await model.run(text) } }
                }
                Button("undo") { Task { await model.run("undo") } }
                    .disabled(!model.canUndo)
                if model.isRunning { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
            .disabled(model.isRunning)

            Text(WindowCommandParser.usage)
                .font(.caption)
                .foregroundStyle(.secondary)

            List(model.log) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("> \(entry.input)").font(.callout.monospaced().bold())
                        if let status = entry.status { StatusBadge(status: status) }
                    }
                    Text(entry.text).font(.caption.monospaced()).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if model.log.isEmpty {
                    Text("Verified results appear here.").foregroundStyle(.secondary)
                }
            }

            Label("Window control acts on real windows. Commands are typed, not spoken; the model is not involved.",
                  systemImage: "macwindow")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
        }
    }
}

private struct PermissionBanner: View {
    let model: WindowControlViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility permission needed").font(.headline)
                Text("macOS must allow Flow to control windows. Flow can't grant this itself. "
                     + "Turn on Flow in System Settings › Privacy & Security › Accessibility.")
                    .font(.callout)
                HStack {
                    Button("Ask macOS") { model.requestPermission() }
                    Button("Open System Settings") { model.openSettings() }
                    Button("Recheck") { model.refreshPermission() }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private struct StatusBadge: View {
    let status: ActionStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .completed: .green
        case .partiallyCompleted, .unverified: .orange
        case .failed: .red
        case .unsupported: .secondary
        }
    }
}
