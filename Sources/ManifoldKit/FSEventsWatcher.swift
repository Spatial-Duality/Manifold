import Foundation
import CoreServices

/// Watches directories for file system changes using macOS FSEvents.
/// Single stream, kernel-efficient batching (~250-500ms latency).
/// Debounces rapid writes to avoid snapshotting mid-save.
public final class FSEventsWatcher: @unchecked Sendable {
    public typealias EventHandler = @Sendable (FSEvent) -> Void

    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let handler: EventHandler
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue

    // Debounce state
    private let pendingLock = NSLock()
    private var pendingTimers: [String: DispatchWorkItem] = [:]

    public init(
        paths: [String],
        debounceInterval: TimeInterval = 0.5,
        handler: @escaping EventHandler
    ) {
        self.paths = paths
        self.handler = handler
        self.debounceInterval = debounceInterval
        self.queue = DispatchQueue(label: "com.manifold.fsevents", qos: .utility)
    }

    deinit {
        stop()
    }

    /// Start watching. Call from main thread or ensure proper lifecycle management.
    public func start() {
        guard stream == nil else { return }

        let cfPaths = paths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let newStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // Latency: 300ms batching
            flags
        ) else { return }

        self.stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    /// Stop watching and clean up.
    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        pendingLock.lock()
        pendingTimers.values.forEach { $0.cancel() }
        pendingTimers.removeAll()
        pendingLock.unlock()
    }

    // MARK: - Internal

    fileprivate func handleRawEvents(paths: [String], flags: [UInt32]) {
        for (path, flag) in zip(paths, flags) {
            let event = FSEvent(path: path, flags: FSEventFlags(flag))

            // Skip directories, only care about files
            guard !event.isDirectory else { continue }
            // Skip our own internal files
            guard !path.contains("manifold.db") else { continue }

            debouncedEmit(event: event)
        }
    }

    private func debouncedEmit(event: FSEvent) {
        pendingLock.lock()

        // Cancel existing timer for this path
        pendingTimers[event.path]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.handler(event)
            self?.pendingLock.lock()
            self?.pendingTimers.removeValue(forKey: event.path)
            self?.pendingLock.unlock()
        }

        pendingTimers[event.path] = workItem
        pendingLock.unlock()

        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

// MARK: - FSEvent

public struct FSEvent: Sendable {
    public let path: String
    public let flags: FSEventFlags

    public var isCreated: Bool { flags.contains(.itemCreated) }
    public var isModified: Bool { flags.contains(.itemModified) }
    public var isRemoved: Bool { flags.contains(.itemRemoved) }
    public var isRenamed: Bool { flags.contains(.itemRenamed) }
    public var isDirectory: Bool { flags.contains(.itemIsDir) }

    public var changeType: ChangeType {
        if isRemoved { return .deleted }
        if isCreated { return .created }
        if isModified { return .modified }
        if isRenamed { return .renamed }
        return .modified // default
    }
}

public enum ChangeType: String, Sendable {
    case created
    case modified
    case deleted
    case renamed
}

// MARK: - FSEventFlags

public struct FSEventFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    init(_ raw: UInt32) { self.rawValue = raw }

    static let itemCreated  = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemCreated))
    static let itemRemoved  = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRemoved))
    static let itemModified = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemModified))
    static let itemRenamed  = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRenamed))
    static let itemIsDir    = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsDir))
    static let itemIsFile   = FSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsFile))
}

// MARK: - C Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo = clientInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientInfo).takeUnretainedValue()

    guard let cfArray = unsafeBitCast(eventPaths, to: CFArray?.self) else { return }
    var paths: [String] = []
    var flags: [UInt32] = []

    for i in 0..<numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfArray, i) {
            let path = unsafeBitCast(cfPath, to: CFString.self) as String
            paths.append(path)
            flags.append(eventFlags[i])
        }
    }

    watcher.handleRawEvents(paths: paths, flags: flags)
}
