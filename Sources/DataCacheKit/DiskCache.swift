import Foundation

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

    private lazy var path: () throws -> URL = {
        let dir = self.options.path
                ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return {
            guard let dir else { throw CocoaError(.fileNoSuchFile) }
            return dir
        }
    }()

    @DiskCacheActor
    private(set) lazy var staging = Staging<Key>()

    @DiskCacheActor
    private var runningTasks: [Key: Task<Void, Error>] = [:]

    @DiskCacheActor
    private var flushingTask: Task<Void, Error>?

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
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    init<C: _Concurrency.Clock>(options: Options, clock: C) where C.Instant.Duration == Duration {
        self.options = options
        self.clock = NewClock(clock)
    }

    public func prepare() throws {
        _ = try path()
    }

    public func cachedData(for key: Key) async throws -> Data? {
        await Task.yield()

        let task = Task<Data?, Error> { @DiskCacheActor in
            if let change = staging.changes[key] {
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
        Task { await _storeData(data, for: key) }
    }

    @discardableResult
    public func removeData(for key: Key) -> Task<Void, Never> {
        Task { await _removeData(for: key) }
    }

    @discardableResult
    public func removeDataAll() -> Task<Void, Never> {
        Task { await _removeDataAll() }
    }

    public func url(for key: Key) -> URL? {
        guard let filename = options.filename(key) else { return nil }
        return try? path().appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: -
    @DiskCacheActor
    private func _storeData(_ data: Data, for key: Key) async {
        await waitForTask(for: key)
        staging.add(data: data, for: key)
        setNeedsFlushChanges()
    }

    @DiskCacheActor
    private func _removeData(for key: Key) async {
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

        let logger = options.logger
        await withTaskGroup(of: Void.self) { group in
            var deleted = false
            var flushedChanges: [Staging<Key>.Change] = []
            var deletedChanges: [Staging<Key>.Change] = []

            let currentStaging = staging
            for change in currentStaging.changes.values {
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

            for change in flushedChanges {
                staging.flushed(change)
            }
        }
    }

    private func performChange(_ change: Staging<Key>.Change, with url: URL) async throws {
        switch change.operation {
        case .add(let data):
            if case let dir = url.deletingLastPathComponent(),
               !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            try data.write(to: url)

        case .remove:
            try FileManager.default.removeItem(at: url)
        }
    }

    private func performChangeRemoveAll() async throws {
        let dir = try path()
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
    struct ChangeRemoveAll {
        let id: Int
    }
    @DiskCacheActor
    enum Operation {
        case add(Data)
        case remove
    }

    private(set) var changes: [Key: Change] = [:]
    private var nextID = 0

    mutating func add(data: Data, for key: Key) {
        nextID &+= 1
        changes[key] = Change(key: key, id: nextID, operation: .add(data))
    }

    mutating func remove(for key: Key) {
        nextID &+= 1
        changes[key] = Change(key: key, id: nextID, operation: .remove)
    }

    mutating func removeAll() {
        nextID &+= 1
        for key in changes.keys {
            changes[key]?.deleted = true
        }
    }

    mutating func flushed(_ change: Change) {
        if let c = changes[change.key], c.id == change.id {
            changes.removeValue(forKey: c.key)
        }
    }
}
