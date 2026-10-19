import SwiftUI
import AppKit

// Settings › AI Assistants (MCP): on / off, status and copyable client setup.
struct MCPSettingsView: View {
    @ObservedObject private var host = MCPHost.shared
    @ObservedObject private var claude = ClaudeDesktopMCP.shared
    @State private var copied: Snippet?
    @State private var claudeMessage: ClaudeMessage?

    private struct ClaudeMessage: Equatable {
        var text: String
        var failed: Bool
    }

    private enum Snippet { case json, claudeCode }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $host.enabled) {
                    Text("Allow AI assistants to use workflows")
                    Text("Claude and other MCP clients can list, run and write your workflows. You approve every new or changed workflow.")
                }
                if host.enabled {
                    LabeledContent("Status") { statusText }
                }
            } footer: {
                Text("AI runs use the same permissions as the Workflow panel: AppPad asks before anything you have not allowed yet. Disabled workflows are hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if host.enabled {
                claudeDesktopSection
                snippetSection(.json, title: "Claude Desktop, Cursor and other clients",
                               caption: "Add this to the client's MCP configuration (Claude Desktop: claude_desktop_config.json), then restart the client.",
                               text: MCPClientConfig.json)
                snippetSection(.claudeCode, title: "Claude Code", caption: "Run once in Terminal.",
                               text: MCPClientConfig.claudeCodeCommand)
            }
        }
        .formStyle(.grouped)
        .onAppear { claude.refresh() }
        // The config may have been edited by hand or by Claude Desktop meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claude.refresh()
        }
    }

    // One-click setup: writes only AppPad's entry into claude_desktop_config.json.
    private var claudeDesktopSection: some View {
        Section {
            LabeledContent("Status") { ClaudeDesktopStatusText(status: claude.status) }
            HStack(spacing: 8) {
                Button("Add to Claude Desktop") { show(claude.add()) }
                    .pillProminentButton()
                    .disabled(!claude.status.canAdd)
                Button("Remove from Claude Desktop") { show(claude.remove()) }
                    .disabled(!claude.status.canRemove)
                Spacer(minLength: 0)
            }
            if let claudeMessage {
                Text(verbatim: claudeMessage.text)
                    .font(.caption)
                    .foregroundStyle(claudeMessage.failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SelectableText(text: "Claude Desktop", font: .boldSystemFont(ofSize: NSFont.systemFontSize))
        } footer: {
            Text("Only AppPad's own entry in claude_desktop_config.json is changed; your other MCP servers stay as they are. A backup of the previous file is kept next to it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func show(_ outcome: Result<String, ClaudeDesktopError>) {
        let message: ClaudeMessage
        switch outcome {
        case .success(let text): message = ClaudeMessage(text: text, failed: false)
        case .failure(let error): message = ClaudeMessage(text: error.message, failed: true)
        }
        claudeMessage = message
        Task {
            try? await Task.sleep(for: .seconds(8))
            if claudeMessage == message { claudeMessage = nil }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if !host.isListening {
            Text("Not running").foregroundStyle(.red)
        } else if host.clientCount == 0 {
            Text("Waiting for a client").foregroundStyle(.secondary)
        } else {
            Text("Connected clients: \(host.clientCount)").foregroundStyle(.green)
        }
    }

    private func snippetSection(_ kind: Snippet, title: String.LocalizationValue, caption: String.LocalizationValue,
                                text: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    // AppKit text view: free drag-select across lines, Cmd+C and context-menu Copy
                    SelectableText(text: text, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied == kind ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy")) {
                        copy(text, kind)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                SelectableText(text: String(localized: caption),
                               font: .preferredFont(forTextStyle: .caption1),
                               color: .secondaryLabelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        } header: {
            SelectableText(text: String(localized: title),
                           font: .boldSystemFont(ofSize: NSFont.systemFontSize))
        }
    }

    private func copy(_ text: String, _ kind: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = kind
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == kind { copied = nil }
        }
    }
}

// Client setup for this exact build (Dev points at its DerivedData copy).
enum MCPClientConfig {
    static var json: String {
        let entry: [String: Any] = ["command": MCPPaths.executablePath, "args": [MCPPaths.proxyArgument]]
        let config: [String: Any] = ["mcpServers": [MCPPaths.serverName: entry]]
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: options) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static var claudeCodeCommand: String {
        "claude mcp add --scope user \(MCPPaths.serverName) -- \(shellQuoted(MCPPaths.executablePath)) \(MCPPaths.proxyArgument)"
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
