import SwiftUI
import AppKit

// Settings › About: app icon, version, official website, open-source acknowledgements.
struct AboutSettingsView: View {
    private static let grdbURL = URL(string: "https://github.com/groue/GRDB.swift")!

    private var appName: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "AppPad"
    }

    private var copyright: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    // Environment icon (Dev / Beta / Release) as shown in Finder.
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 112, height: 112)
                    Text(verbatim: appName)
                        .font(.title2.weight(.semibold))
                    if let copyright {
                        Text(verbatim: copyright)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Section {
                LabeledContent("Version") {
                    Text(verbatim: AppEnvironment.versionNumber)
                        .textSelection(.enabled)
                }
                LabeledContent("Website") {
                    Link(AppEnvironment.websiteURL.host() ?? AppEnvironment.websiteURL.absoluteString,
                         destination: AppEnvironment.websiteURL)
                }
            }

            Section("Acknowledgements") {
                // Name + description on the left, GitHub icon vertically centered on the right.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "GRDB.swift")
                        Text("A toolkit for SQLite databases. MIT License.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    GitHubIconLink(url: Self.grdbURL)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - GitHub icon link

// Icon-only link in primary color; slight fade on hover.
private struct GitHubIconLink: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        Link(destination: url) {
            Image(nsImage: GitHubMark.image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)
                .opacity(hovering ? 0.7 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(url.absoluteString)
        .accessibilityLabel(Text(verbatim: "GitHub"))
    }
}

// GitHub mark (octicon) as vector template image; follows light/dark mode.
private enum GitHubMark {
    static let image: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16">\
        <path fill="#000" fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 \
        0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 \
        1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15\
        -.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82\
        .44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93\
        -.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>
        """
        // NSImage decodes SVG natively on macOS 14+; fall back to an SF Symbol.
        let img = NSImage(data: Data(svg.utf8))
            ?? NSImage(systemSymbolName: "link", accessibilityDescription: "GitHub")
            ?? NSImage()
        img.isTemplate = true
        return img
    }()
}
