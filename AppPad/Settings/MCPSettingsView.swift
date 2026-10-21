import SwiftUI
import AppKit

// Settings › AI Assistants (MCP): on / off, status, app installs (Homebrew) and copyable client setup.
struct MCPSettingsView: View {
    @ObservedObject private var host = MCPHost.shared
    @ObservedObject private var claude = ClaudeDesktopMCP.shared
    @State private var copied: Snippet?
    @State private var claudeMessage: ClaudeMessage?
    @State private var homebrewInstalled = Homebrew.isInstalled

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
                    LabeledContent(String(localized: "Status", table: "MCP")) { statusText }
                }
            } footer: {
                Text("AI runs use the same permissions as the Workflow panel: AppPad asks before anything you have not allowed yet. Disabled workflows are hidden.", tableName: "MCP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if host.enabled {
                appsSection
                claudeDesktopSection
                snippetSection(.json, title: String(localized: "Claude Desktop, Cursor and other clients"),
                               caption: String(localized: "Add this to the client's MCP configuration (Claude Desktop: claude_desktop_config.json), then restart the client."),
                               text: MCPClientConfig.json)
                snippetSection(.claudeCode, title: String(localized: "Claude Code", table: "MCP"), caption: String(localized: "Run once in Terminal."),
                               text: MCPClientConfig.claudeCodeCommand)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            claude.refresh()
            homebrewInstalled = Homebrew.isInstalled
        }
        // The config may have been edited by hand or by Claude Desktop meanwhile (Homebrew installed in Terminal).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            claude.refresh()
            homebrewInstalled = Homebrew.isInstalled
        }
    }

    // AI installs / uninstalls of apps through Homebrew casks.
    private var appsSection: some View {
        Section {
            Toggle(isOn: $host.confirmAppChanges) {
                Text("Confirm before AI installs or uninstalls apps", tableName: "MCP")
                Text("Shows the app, its developer and where it comes from before anything changes.", tableName: "MCP")
            }
            if !host.confirmAppChanges {
                autoInstallWarning
            }
            LabeledContent(String(localized: "Homebrew", table: "MCP")) {
                if homebrewInstalled {
                    Text("Installed", tableName: "MCP").foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        Text("Not installed", tableName: "MCP").foregroundStyle(.secondary)
                        Button(String(localized: "Install…", table: "MCP")) { try? HomebrewInstaller.openInTerminal() }
                    }
                }
            }
        } header: {
            SelectableText(text: String(localized: "Apps"), font: .boldSystemFont(ofSize: NSFont.systemFontSize))
        } footer: {
            Text("AI assistants can install apps from Homebrew’s official catalog that are notarized by Apple and contain only the app, including command-line tools that live inside it. Formulae, installers and third-party taps are not supported.", tableName: "MCP")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // Shown while confirmation is off: the risk must be visible, not buried in a footer.
    private static let autoInstallRisks: [String] = [
        String(localized: "The AI can be misled by something it reads, such as a web page, a document or an email, and install an app you never wanted.", table: "MCP"),
        String(localized: "Notarized does not mean harmless: remote-control tools and similar software pass every check.", table: "MCP"),
        String(localized: "The AI can uninstall apps you use.", table: "MCP"),
        String(localized: "Uninstalling an app with Homebrew deletes it right away instead of moving it to the Trash, so work may be lost (it cannot be restored).", table: "MCP"),
    ]

    private var autoInstallWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("AI can install and uninstall apps without asking", tableName: "MCP")
                    .fontWeight(.semibold)
                ForEach(Array(Self.autoInstallRisks.enumerated()), id: \.offset) { index, risk in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "\(index + 1).circle.fill")
                        Text(risk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
                Text("Turn confirmation back on unless you watch every AI request yourself.", tableName: "MCP")
                    .font(.callout)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .foregroundStyle(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.6), lineWidth: 1))
    }

    // One-click setup: writes only AppPad's entry into claude_desktop_config.json.
    private var claudeDesktopSection: some View {
        Section {
            LabeledContent(String(localized: "Status", table: "MCP")) { ClaudeDesktopStatusText(status: claude.status) }
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
            Text("Only AppPad's own entry in claude_desktop_config.json is changed; your other MCP servers stay as they are. A backup of the previous file is kept next to it.", tableName: "MCP")
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

    private func snippetSection(_ kind: Snippet, title: String, caption: String,
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
                SelectableText(text: caption,
                               font: .preferredFont(forTextStyle: .caption1),
                               color: .secondaryLabelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        } header: {
            SelectableText(text: title,
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
