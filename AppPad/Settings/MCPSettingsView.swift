import SwiftUI
import AppKit

// Settings › AI Assistants (MCP): on / off, status and copyable client setup.
struct MCPSettingsView: View {
    @ObservedObject private var host = MCPHost.shared
    @State private var copied: Snippet?

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
                snippetSection(.json, title: "Claude Desktop, Cursor and other clients",
                               caption: "Add this to the client's MCP configuration (Claude Desktop: claude_desktop_config.json), then restart the client.",
                               text: MCPClientConfig.json)
                snippetSection(.claudeCode, title: "Claude Code", caption: "Run once in Terminal.",
                               text: MCPClientConfig.claudeCodeCommand)
            }
        }
        .formStyle(.grouped)
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
