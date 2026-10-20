import AppKit

// Before install: `brew fetch` the download, open it read-only (dmg / zip / tar), and check every
// app with Gatekeeper (`spctl`): it must be "Notarized Developer ID", all apps from one team.
// Command-line tools must be files inside those apps (sealed by their signature).
// After install: the apps in the Applications folder carry the same Team ID, and every tool link in
// brew's bin folder resolves into one of them.
nonisolated enum CaskVerifier {
    nonisolated struct Signature: Sendable, Equatable {
        let developer: String
        let teamID: String
    }

    // A download opened for inspection; call cleanup() when done.
    nonisolated struct Staged: Sendable {
        let apps: [URL]
        let signature: Signature
        let tempDir: URL
        let mountPoints: [String]
    }

    nonisolated struct Failure: LocalizedError, Sendable {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private enum Format { case dmg, zip, tar }

    // MARK: - Download

    static func fetch(_ cask: CaskInfo) async throws -> URL {
        let output = try await Homebrew.run(["fetch", "--cask", cask.token], timeout: 3600)
        guard output.succeeded else { throw Failure("Download failed: " + Homebrew.errorText(output)) }
        let cache = try await Homebrew.run(["--cache", "--cask", cask.token], timeout: 30)
        let path = cache.stdout.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard cache.succeeded, !path.isEmpty, FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("Homebrew did not report the downloaded file.")
        }
        return url
    }

    // MARK: - Stage

    static func stage(_ download: URL, cask: CaskInfo) async throws -> Staged {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("AppPad-Cask-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var mounts: [String] = []
        do {
            let roots: [URL]
            switch try format(of: download) {
            case .dmg:
                mounts = try await attach(download, tempDir: tempDir)
                roots = mounts.map { URL(fileURLWithPath: $0, isDirectory: true) }
            case .zip:
                let dest = tempDir.appendingPathComponent("unpacked", isDirectory: true)
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                let out = await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", download.path, dest.path], timeout: 600)
                guard out.succeeded else { throw Failure("Could not unpack the download: " + Homebrew.errorText(out)) }
                roots = [dest]
            case .tar:
                let dest = tempDir.appendingPathComponent("unpacked", isDirectory: true)
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                let out = await ProcessRunner.run("/usr/bin/tar", ["-xf", download.path, "-C", dest.path], timeout: 600)
                guard out.succeeded else { throw Failure("Could not unpack the download: " + Homebrew.errorText(out)) }
                roots = [dest]
            }
            var apps: [URL] = []
            for app in cask.apps {
                guard let url = locate(app, in: roots) else {
                    throw Failure("\(app.source) was not found in the download.")
                }
                apps.append(url)
            }
            let signature = try await commonSignature(apps)
            try checkTools(cask, apps: Dictionary(zip(cask.apps.map(\.target), apps), uniquingKeysWith: { a, _ in a }))
            return Staged(apps: apps, signature: signature, tempDir: tempDir, mountPoints: mounts)
        } catch {
            await cleanup(mountPoints: mounts, tempDir: tempDir)
            throw error
        }
    }

    static func cleanup(_ staged: Staged) async {
        await cleanup(mountPoints: staged.mountPoints, tempDir: staged.tempDir)
    }

    private static func cleanup(mountPoints: [String], tempDir: URL) async {
        for mount in mountPoints {
            _ = await ProcessRunner.run("/usr/bin/hdiutil", ["detach", mount, "-force"], timeout: 60)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    // By content, not extension (cache names often have none). The disk image trailer is checked
    // first: a compressed dmg starts with its first compressed chunk (bzip2 "BZh", zlib…), which
    // would otherwise look like an archive.
    private static func format(of url: URL) throws -> Format {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure("Could not read the download.") }
        defer { try? handle.close() }
        // UDIF disk image: "koly" trailer in the last 512 bytes.
        if let size = try? handle.seekToEnd(), size >= 512 {
            try? handle.seek(toOffset: size - 512)
            if let trailer = try? handle.read(upToCount: 4), trailer == Data("koly".utf8) { return .dmg }
        }
        try? handle.seek(toOffset: 0)
        let bytes = [UInt8]((try? handle.read(upToCount: 6)) ?? Data())
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .zip }
        if bytes.starts(with: [0x1F, 0x8B]) || bytes.starts(with: [0x42, 0x5A, 0x68])
            || bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .tar }
        throw Failure("The download is not a disk image or archive AppPad can check.")
    }

    // Same approach as Homebrew: try without the license agreement, else convert (drops it) and attach.
    private static func attach(_ dmg: URL, tempDir: URL) async throws -> [String] {
        let mountRoot = tempDir.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountRoot, withIntermediateDirectories: true)
        let args = ["attach", "-plist", "-nobrowse", "-readonly", "-noautoopen", "-mountrandom", mountRoot.path]
        var out = await ProcessRunner.run("/usr/bin/hdiutil", args + [dmg.path], stdin: Data("qn\n".utf8), timeout: 300)
        if !out.succeeded {
            let cdr = tempDir.appendingPathComponent("image.cdr")
            let convert = await ProcessRunner.run("/usr/bin/hdiutil",
                                                  ["convert", "-quiet", "-format", "UDTO", "-o", cdr.path, dmg.path],
                                                  timeout: 900)
            guard convert.succeeded else { throw Failure("Could not open the disk image: " + Homebrew.errorText(convert)) }
            out = await ProcessRunner.run("/usr/bin/hdiutil", args + [cdr.path], timeout: 300)
        }
        guard out.succeeded, let data = out.stdout.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw Failure("Could not open the disk image: " + Homebrew.errorText(out))
        }
        let mounts = entities.compactMap { $0["mount-point"] as? String }
        guard !mounts.isEmpty else { throw Failure("The disk image has no readable volume.") }
        return mounts
    }

    // The cask's exact path first, then the app name up to 3 folders deep.
    private static func locate(_ app: CaskInfo.App, in roots: [URL]) -> URL? {
        let fm = FileManager.default
        func isApp(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue && url.pathExtension == "app"
        }
        for root in roots {
            let exact = root.appendingPathComponent(app.source)
            if isApp(exact) { return exact }
        }
        let name = (app.source as NSString).lastPathComponent
        for root in roots {
            var queue: [(URL, Int)] = [(root, 0)]
            while !queue.isEmpty {
                let (dir, depth) = queue.removeFirst()
                let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                for item in items {
                    if item.lastPathComponent == name, isApp(item) { return item }
                    if depth < 3, item.pathExtension != "app",
                       (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        queue.append((item, depth + 1))
                    }
                }
            }
        }
        return nil
    }

    // Each tool is a regular file (or a link resolving) inside its app bundle.
    private static func checkTools(_ cask: CaskInfo, apps: [String: URL]) throws {
        for tool in cask.tools {
            guard let app = apps[tool.app] else { throw Failure("\(tool.name) belongs to no app of this download.") }
            let file = app.appendingPathComponent(tool.inner)
            guard isInside(file, app), FileManager.default.fileExists(atPath: file.path) else {
                throw Failure("The command-line tool \(tool.name) was not found inside \(tool.app).")
            }
        }
    }

    private static func isInside(_ file: URL, _ bundle: URL) -> Bool {
        let base = bundle.resolvingSymlinksInPath().standardizedFileURL.path
        let path = file.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(base + "/")
    }

    // MARK: - Gatekeeper

    private static func commonSignature(_ apps: [URL]) async throws -> Signature {
        var first: Signature?
        for app in apps {
            let signature = try await notarizedSignature(app)
            if let first, first.teamID != signature.teamID {
                throw Failure("The apps in this download are signed by different developers.")
            }
            first = first ?? signature
        }
        guard let first else { throw Failure("The download contains no app.") }
        return first
    }

    // spctl -vv prints "source=Notarized Developer ID" and "origin=Developer ID Application: Name (TEAMID)".
    static func notarizedSignature(_ app: URL) async throws -> Signature {
        let out = await ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "-vv", app.path], timeout: 120)
        let text = out.stderr + "\n" + out.stdout
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let source = lines.first { $0.hasPrefix("source=") }.map { String($0.dropFirst("source=".count)) } ?? ""
        let origin = lines.first { $0.hasPrefix("origin=") }.map { String($0.dropFirst("origin=".count)) } ?? ""
        let name = app.deletingPathExtension().lastPathComponent
        guard out.succeeded, source == "Notarized Developer ID" else {
            throw Failure("\(name) is not notarized by Apple" + (source.isEmpty ? "." : " (\(source))."))
        }
        guard let signature = parse(origin) else { throw Failure("\(name) has no readable developer signature.") }
        return signature
    }

    // "Developer ID Application: Mozilla Corporation (43AQ936H96)"
    private static func parse(_ origin: String) -> Signature? {
        guard origin.hasSuffix(")"), let open = origin.range(of: " (", options: .backwards) else { return nil }
        let team = String(origin[open.upperBound..<origin.index(before: origin.endIndex)])
        var developer = String(origin[..<open.lowerBound])
        if let colon = developer.range(of: ": ") { developer = String(developer[colon.upperBound...]) }
        guard !team.isEmpty, team.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return Signature(developer: developer, teamID: team)
    }

    // MARK: - After install

    // Installed copies at brew's target path, each with the expected Team ID.
    static func verifyInstalled(_ cask: CaskInfo, expected: Signature) async throws -> [URL] {
        let fm = FileManager.default
        var installed: [URL] = []
        for app in cask.apps {
            let url = URL(fileURLWithPath: app.path, isDirectory: true)
            guard fm.fileExists(atPath: url.path) else {
                throw Failure("\(app.target) was not found in the Applications folder after installing.")
            }
            let signature = try await notarizedSignature(url)
            guard signature.teamID == expected.teamID else {
                throw Failure("\(app.target) is signed by \(signature.developer) (\(signature.teamID)), not by the checked developer.")
            }
            installed.append(url)
        }
        // brew links tools next to itself (<prefix>/bin); each link must end inside an installed app.
        if !cask.tools.isEmpty {
            guard let brew = Homebrew.executable else { throw HomebrewError.notInstalled }
            let binDir = URL(fileURLWithPath: (brew as NSString).deletingLastPathComponent, isDirectory: true)
            for tool in cask.tools {
                let link = binDir.appendingPathComponent(tool.name)
                guard fm.fileExists(atPath: link.path), installed.contains(where: { isInside(link, $0) }) else {
                    throw Failure("The command-line tool \(tool.name) does not point into the installed app.")
                }
            }
        }
        return installed
    }

    // Target path already taken (not by this cask).
    static func existingTargets(_ cask: CaskInfo) -> [String] {
        cask.apps.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.target)
    }
}
