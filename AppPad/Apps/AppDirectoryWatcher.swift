import Foundation
import CoreServices

// FSEvents watcher for application folders; fires onChange on the main queue.
// Lives for the whole app lifetime, so the stream is never torn down.
final class AppDirectoryWatcher {
    private static weak var current: AppDirectoryWatcher?

    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        Self.current = self
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.makeCallback(),
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    nonisolated private static func makeCallback() -> FSEventStreamCallback {
        return { _, _, _, _, _, _ in
            MainActor.assumeIsolated {
                AppDirectoryWatcher.current?.onChange()
            }
        }
    }
}
