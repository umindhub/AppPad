import SwiftUI
import AppKit

// Result of a run started from Settings: per-step output, denied permissions, sandbox debugging.
struct WorkflowResultView: View {
    let result: WorkflowRunResult
    let onClose: () -> Void

    @State private var denials: [String]?
    @State private var loadingDenials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let message = result.message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if !result.denied.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not allowed for this run:", tableName: "WorkflowEditor")
                                .font(.callout.weight(.semibold))
                            ForEach(result.denied) { item in
                                Text(verbatim: "• " + item.title).font(.callout)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    ForEach(result.steps) { step in
                        stepView(step)
                    }
                    if let denials {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sandbox denials", tableName: "WorkflowEditor")
                                .font(.callout.weight(.semibold))
                            if denials.isEmpty {
                                Text("No sandbox denials were logged for this run.", tableName: "WorkflowEditor")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: denials.joined(separator: "\n"))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("Declare the missing paths or services under Declared Permissions.", tableName: "WorkflowEditor")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if result.sandboxProfile != nil {
                    Button(loadingDenials ? String(localized: "Reading Log…", table: "WorkflowEditor") : String(localized: "Show Sandbox Denials", table: "WorkflowEditor"),
                           action: loadDenials)
                        .disabled(loadingDenials)
                    Button(String(localized: "Copy Sandbox Profile", table: "WorkflowEditor")) { copy(result.sandboxProfile ?? "") }
                }
                Spacer()
                Button(String(localized: "Copy Output", table: "WorkflowEditor")) { copy(result.finalOutput) }
                    .disabled(result.finalOutput.isEmpty)
                Button(String(localized: "Done", table: "Workflow"), action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .pillProminentButton()
            }
        }
        .padding(16)
        .frame(width: 560, height: 480)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.title)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.workflowName)
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepView(_ step: StepResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: step.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(step.success ? Color.green : Color.red)
                Text(verbatim: step.title).font(.callout.weight(.semibold))
                Spacer()
                Text(verbatim: String(format: "%.2f s", step.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = step.message {
                Text(verbatim: message).font(.callout).foregroundStyle(.red)
            }
            if !step.output.isEmpty {
                outputBlock(step.output)
            }
            if !step.stderr.isEmpty {
                outputBlock(step.stderr, color: .orange)
            }
        }
    }

    private func outputBlock(_ text: String, color: Color = .primary) -> some View {
        Text(verbatim: text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }

    private var statusSymbol: String {
        if result.cancelled { return "stop.circle.fill" }
        return result.success ? "checkmark.circle.fill" : "xmark.octagon.fill"
    }

    private var statusColor: Color {
        if result.cancelled { return .secondary }
        return result.success ? .green : .red
    }

    private var statusText: String {
        let seconds = String(format: "%.2f", result.finishedAt.timeIntervalSince(result.startedAt))
        if result.cancelled { return String(localized: "Cancelled after \(seconds) s", table: "WorkflowEditor") }
        return result.success
            ? String(localized: "Finished in \(seconds) s", table: "WorkflowEditor")
            : String(localized: "Failed after \(seconds) s", table: "WorkflowEditor")
    }

    private func loadDenials() {
        loadingDenials = true
        Task {
            denials = await SandboxLog.denials(from: result.startedAt, to: result.finishedAt)
            loadingDenials = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
