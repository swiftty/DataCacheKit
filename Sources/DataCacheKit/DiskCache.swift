// The MIT License (MIT)
//
// This implementation is based on kean/Nuke's DataCache
// https://github.com/kean/Nuke/blob/master/Sources/Core/Caching/DataCache.swift

import Foundation
import OSLog

@globalActor
public struct DiskCacheActor {
    private actor _Actor {}

    public static let shared: some Actor & AnyObject = _Actor()
}

// MARK: - DiskCache
public final class DiskCache<Key: Hashable & Sendable> {
    public let options: Options

    public subscript (key: Key) -> Data? {
        get async throws {
            try await cachedData(for: key)
        }
//        set {
//            if let newValue {
//                storeData(newValue, for: key)
//            } else {
//                removeData(for: key)
//            }
//        }
    }

    private let clock: _Clock

    private var path: URL {
        get throws {
            try _prepare()
            return _path
        }
    }
    private var _path: URL!

    private lazy var _prepare: () throws -> Void = {
        let dir = options.path
                ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        _path = dir
        Task {
            await scheduleSweep(after: 10)
        }
        return {
            if dir == nil {
                throw CocoaError(.fileNoSuchFile)
            }
        }
    }()

    private let queueingLock = NSLock()
    private var queueingTask: Task<Void, Never>?

    @DiskCacheActor
    private(set) lazy var staging = Staging<Key>()

    @DiskCacheActor
    private var runningTasks: [Key: Task<Void, Error>] = [:]

    @DiskCacheActor
    private var flushingTask: Task<Void, Error>?

    @DiskCacheActor
    private var sweepingTask: Task<Void, Error>?

    @DiskCacheActor
    private var isFlushNeeded = false

    @DiskCacheActor
    private var isFlushScheduled = false

    public init(options: Options) {
        self.options = options
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            self.clock = NewClock(.suspending)
        } else {
            self.clock = _Clock()
        }
        try? _prepare()
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    init<C: _Concurrency.Clock>(options: Options, clock: C) where C.Instant.Duration == Duration {
        self.options = options
        self.clock = NewClock(clock)
        try? _prepare()
    }

    public func prepare() throws {
        try _prepare()
    }

    public func cachedData(for key: Key) async throws -> Data? {
        await Task.yield()

        let task = Task<Data?, Error> { @DiskCacheActor in
            if let change = staging.changes(for: key) {
                if change.deleted {
                    return nil
                }
                switch change.operation {
                case .add(let data): return data
                case .remove: return nil
                }
            }

            guard let url = url(for: key) else { return nil }

            await waitForTask(for: key)

            let task = Task<Data?, Error>.detached {
                do {
                    return try Data(contentsOf: url)
                } catch CocoaError.fileNoSuchFile {
                    return nil
                }
            }
            return try await task.value
        }
        return try await task.value
    }

    @discardableResult
    public func storeData(_ data: Data, for key: Key) -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            await _storeData(data, for: key)
        }
        queueingTask = task
        return task
    }

    @discardableResult
    public func removeData(for key: Key) -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            await _removeData(for: key)
        }
        queueingTask = task
        return task
    }

    @discardableResult
    public func removeDataAll() -> Task<Void, Never> {
        queueingLock.lock()
        defer { queueingLock.unlock() }
        let oldTask = queueingTask
        let task = Task {
            await oldTask?.value
            await _removeDataAll()
        }
        queueingTask = task
        return task
    }

    public func url(for key: Key) -> URL? {
        guard let filename = options.filename(key) else { return nil }
        return try? path.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: -
    @DiskCacheActor
    private func _storeData(_ data: Data, for key: Key) async {
        options.logger.debug("store data: \(data) for \(String(describing: key))")
        await waitForTask(for: key)
        staging.add(data: data, for: key)
        setNeedsFlushChanges()
    }

    @DiskCacheActor
    private func _removeData(for key: Key) async {
        options.logger.debug("remove data for \(String(describing: key))")
        await waitForTask(for: key)
        staging.remove(for: key)
        setNeedsFlushChanges()
    }

    @DiskCacheActor
    private func _removeDataAll() async {
        _ = await flushingTask?.result
        staging.removeAll()
        setNeedsFlushChanges()
    }

    @DiskCacheActor
    private func waitForTask(for key: Key) async {
        guard let task = runningTasks[key] else { return }
        _ = await task.result
    }
}

extension DiskCache {
    @DiskCacheActor
    private func setNeedsFlushChanges() {
        guard !isFlushNeeded else { return }
        isFlushNeeded = true

        options.logger.debug("flush scheduled")

        let oldTask = flushingTask
        flushingTask = Task {
            try await clock.sleep(until: 1)
            _ = await oldTask?.result
            await flushIfNeeded()
        }
    }

    @DiskCacheActor
    private func flushIfNeeded() async {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        defer { isFlushScheduled = false }

        guard isFlushNeeded else { return }
        isFlushNeeded = false

        options.logger.debug("flush starting")
        await _flushIfNeeded(numberOfAttempts: staging.stages.count)
    }

    @DiskCacheActor
    private func _flushIfNeeded(numberOfAttempts: Int) async {
        func _peformChange(_ change: Staging<Key>.Change, with url: URL) -> Task<Void, Error> {
            let task = Task {
                try await performChange(change, with: url)
            }
            assert(runningTasks[change.key] == nil)
            runningTasks[change.key] = task
            Task {
                _ = await task.result
                runningTasks.removeValue(forKey: change.key)
            }

            return task
        }
        func _performChangeRemoveAll(for changes: [Staging<Key>.Change]) -> Task<Void, Error> {
            let task = Task<Void, Error> {
                do {
                    try await performChangeRemoveAll()
                } catch {
                    logger.error("\(String(describing: error))")
                }
            }
            for change in changes {
                assert(runningTasks[change.key] == nil)
                runningTasks[change.key] = task
                Task {
                    _ = await task.result
                    runningTasks.removeValue(forKey: change.key)
                }
            }
            return task
        }

        guard numberOfAttempts > 0, let stage = staging.stages.first else { return }
        let logger = options.logger
        let changes = await withTaskGroup(of: Void.self, returning: [Staging<Key>.Change].self) { group in
            var deleted = false
            var flushedChanges: [Staging<Key>.Change] = []
            var deletedChanges: [Staging<Key>.Change] = []

            for change in stage.changes.values {
                if change.deleted {
                    deleted = deleted || change.deleted
                    deletedChanges.append(change)
                } else {
                    guard let url = url(for: change.key) else {
                        flushedChanges.append(change)
                        continue
                    }
                    let task = _peformChange(change, with: url)
                    group.addTask { @DiskCacheActor in
                        do {
                            try await task.value
                            flushedChanges.append(change)
                        } catch {
                            logger.error("\(String(describing: error))")
                        }
                    }
                }
            }

            await group.waitForAll()

            if deleted {
                let task = _performChangeRemoveAll(for: deletedChanges)
                do {
                    try await task.value
                    flushedChanges.append(contentsOf: deletedChanges)
                } catch {}
            }

            return flushedChanges
        }

        for change in changes {
            staging.flushed(change, with: options.logger)
        }

        if !staging.stages.isEmpty {
            await _flushIfNeeded(numberOfAttempts: numberOfAttempts - 1)
        }
    }

    @DiskCacheActor
    private func performChange(_ change: Staging<Key>.Change, with url: URL) async throws {
        switch change.operation {
        case .add(let data):
            if case let dir = url.deletingLastPathComponent(),
               !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            options.logger.debug("add data: \(data) to \(url.lastPathComponent)")
            try data.write(to: url)

        case .remove:
            options.logger.debug("remove data at \(url.lastPathComponent)")
            try FileManager.default.removeItem(at: url)
        }
    }

    @DiskCacheActor
    private func performChangeRemoveAll() async throws {
        let dir = try path
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

extension DiskCache {
    @DiskCacheActor
    private func scheduleSweep(after seconds: Int) {
        options.logger.debug("sweep scheduled")
        let oldTask = sweepingTask
        sweepingTask = Task {
            try await clock.sleep(until: seconds)
            _ = await oldTask?.result
            do {
                try performSweep()
            } catch {
                options.logger.error("sweep error: \(String(describing: error))")
            }
            scheduleSweep(after: 30)
        }
    }

    @DiskCacheActor
    private func performSweep() throws {
        var items = try contents(keys: [.contentAccessDateKey, .totalFileAllocatedSizeKey])
        guard !items.isEmpty else { return }

        var size = items.reduce(0) { $0 + ($1.meta.totalFileAllocatedSize ?? 0) }

        guard size > options.sizeLimit else { return }

        let sizeLimit = Int(Double(options.sizeLimit) * 0.7)
        items = items.sorted(by: { lhs, rhs in
            (lhs.meta.contentAccessDate ?? .distantPast) > (rhs.meta.contentAccessDate ?? .distantPast)
        })

        while sizeLimit > sizeLimit, let item = items.popLast() {
            do {
                try FileManager.default.removeItem(at: item.url)
                size -= item.meta.totalFileAllocatedSize ?? 0
            } catch {
                options.logger.error("sweep item: \(item.url.lastPathComponent), error: \(String(describing: error))")
            }
        }
    }

    private struct Entry {
        let url: URL
        let meta: URLResourceValues
    }

    @DiskCacheActor
    private func contents(keys: [URLResourceKey] = []) throws -> [Entry] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: path, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        let keys = Set(keys)
        return urls.compactMap { url in
            guard let meta = try? url.resourceValues(forKeys: keys) else { return nil }
            return Entry(url: url, meta: meta)
        }
    }

    /// The total number of items in the cache.
    public var totalCount: Int {
        get async throws {
            try await contents().count
        }
    }

    /// The total file size of items written on disk.
    ///
    /// Uses `URLResourceKey.fileSizeKey` to calculate the size of each entry.
    /// The total allocated size (see `totalAllocatedSize`. on disk might
    /// actually be bigger.
    public var totalSize: Int {
        get async throws {
            try await contents(keys: [.fileSizeKey]).reduce(0) {
                $0 + ($1.meta.fileSize ?? 0)
            }
        }
    }

    /// The total file allocated size of all the items written on disk.
    ///
    /// Uses `URLResourceKey.totalFileAllocatedSizeKey`.
    public var totalAllocatedSize: Int {
        get async throws {
            try await contents(keys: [.totalFileAllocatedSizeKey]).reduce(0) {
                $0 + ($1.meta.totalFileAllocatedSize ?? 0)
            }
        }
    }
}

extension DiskCache {
    class _Clock {
        func sleep(until seconds: Int) async throws {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    final class NewClock<C: Clock>: _Clock where C.Instant.Duration == Duration {
        let clock: C

        init(_ clock: C) {
            self.clock = clock
        }

        override func sleep(until seconds: Int) async throws {
            try await clock.sleep(until: clock.now.advanced(by: .seconds(seconds)), tolerance: nil)
        }
    }
}

@DiskCacheActor
struct Staging<Key: Hashable & Sendable> {
    @DiskCacheActor
    struct Change {
        let key: Key
        let id: Int
        let operation: Operation
        var deleted = false
    }
    @DiskCacheActor
    enum Operation: Equatable {
        case add(Data)
        case remove
    }
    @DiskCacheActor
    struct Stage {
        let id: Int
        var changes: [Key: Change]
    }

    private(set) var stages: [Stage] = []
    private var stageID = IDGenerator()
    private var changeID = IDGenerator()

    func changes(for key: Key) -> Change? {
        for stage in stages.reversed() {
            if let change = stage.changes[key] {
                return change
            }
        }
        return nil
    }

    mutating func add(data: Data, for key: Key) {
        let change = Change(key: key, id: changeID.nextID(), operation: .add(data))
        if checkConflicts(on: key) {
            stages.append(Stage(id: stageID.nextID(), changes: [key: change]))
        } else {
            stages[stages.count - 1].changes[key] = change
        }
    }

    mutating func remove(for key: Key) {
        let change = Change(key: key, id: changeID.nextID(), operation: .remove)
        if checkConflicts(on: key) {
            stages.append(Stage(id: stageID.nextID(),changes: [key: change]))
        } else {
            stages[stages.count - 1].changes[key] = change
        }
    }

    mutating func removeAll() {
        var keys: Set<Key> = []
        for stage in stages {
            for change in stage.changes.values {
                keys.insert(change.key)
            }
        }
        var stage = Stage(id: stageID.nextID(), changes: [:])
        for key in keys {
            stage.changes[key] = Change(key: key, id: changeID.nextID(), operation: .remove, deleted: true)
        }
        stages.append(stage)
    }

    mutating func flushed(_ change: Change, with logger: Logger) {
        for (i, var stage) in stages.enumerated() {
            guard let c = stage.changes[change.key], c.id == change.id else { continue }
            stage.changes.removeValue(forKey: c.key)
            if stage.changes.isEmpty {
                stages.remove(at: i)
                logger.debug("flushed change \(String(describing: c.key)), at stage: \(stage.id), removed")
            } else {
                stages[i] = stage
                logger.debug("flushed change \(String(describing: c.key)), at stage: \(stage.id)")
            }
            return
        }
    }

    private func checkConflicts(on key: Key? = nil) -> Bool {
        guard let stage = stages.last else { return true }
        if stage.changes.values.contains(where: \.deleted) { return true }
        if let key, stage.changes.keys.contains(key) { return true }
        return false
    }
}

private struct IDGenerator {
    private var _nextID = 0

    mutating func nextID() -> Int {
        defer { _nextID &+= 1 }
        return _nextID
    }
}
