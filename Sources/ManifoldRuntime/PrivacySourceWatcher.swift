// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import CoreServices
import Foundation
import ManifoldKit

actor PrivacySourceWatcher {
    let source: SourceRecord
    private let relay: Relay

    init(source: SourceRecord, onEvents: @escaping @Sendable ([String]) async -> Void) {
        self.source = source
        self.relay = Relay(rootPath: source.effectiveRootPath) { paths in
            Task { await onEvents(paths) }
        }
        relay.start()
    }

    func stop() {
        relay.stop()
    }
}

private final class Relay {
    private let rootPath: String
    private let queue: DispatchQueue
    private let callback: @Sendable ([String]) -> Void
    private var stream: FSEventStreamRef?
    private var pendingPaths: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?

    init(rootPath: String, callback: @escaping @Sendable ([String]) -> Void) {
        self.rootPath = rootPath
        self.callback = callback
        self.queue = DispatchQueue(label: "com.spatialduality.manifold.privacy-source-watcher.\(UUID().uuidString)")
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes
            )
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingPaths.removeAll()

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(paths: [String]) {
        pendingPaths.formUnion(paths)
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let events = Array(self.pendingPaths).sorted()
            self.pendingPaths.removeAll()
            self.callback(events)
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPathsPointer, _, _ in
        guard let info else { return }
        let relay = Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue()
        let events = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String] ?? []
        relay.handle(paths: Array(events.prefix(Int(numEvents))))
    }

    deinit {
        stop()
    }
}
