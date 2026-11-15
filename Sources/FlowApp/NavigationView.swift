import FlowAX
import SwiftUI

struct NavigationView: View {
    @Bindable var model: NavigationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Navigation command, e.g. “click the Save button in Calculator”", text: $model.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospaced())
                    .onSubmit { model.submit() }
                    .accessibilityLabel("Navigation command")
                Button("Run") { model.submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                ForEach(["show numbers", "hide numbers", "inspect", "scroll down", "scroll up"], id: \.self) { text in
                    Button(text) { Task { await model.run(text) } }
                }
                if model.isRunning { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
            .disabled(model.isRunning)

            if !model.numbers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Numbered targets (also shown on screen)").font(.headline)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(model.numbers, id: \.number) { target in
                                Button("\(target.number): \(target.element.displayName)") {
                                    Task { await model.run("choose \(target.number)") }
                                }
                                .accessibilityLabel("Choose \(target.number), \(target.element.displayName)")
                            }
                        }
                    }
                }
                .controlSize(.small)
            }

            Text(NavCommandParser.usage)
                .font(.caption)
                .foregroundStyle(.secondary)

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
                .padding(.vertical, 2)
            }
            .overlay {
                if model.log.isEmpty {
                    Text("Commands act on the app you used before Flow (or “in <app>”).").foregroundStyle(.secondary)
                }
            }

            Label("Typed commands only. The classifier's output is not connected to execution.", systemImage: "cursorarrow.click")
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
