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
                LabeledContent {
                    Link(destination: Self.grdbURL) {
                        Text(verbatim: "GitHub")
                    }
                } label: {
                    Text(verbatim: "GRDB.swift")
                    Text("A toolkit for SQLite databases. MIT License.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
