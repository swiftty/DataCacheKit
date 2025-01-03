// The MIT License (MIT)
//
// This implementation is based on kean/Nuke's DataCache
// https://github.com/kean/Nuke/blob/master/Sources/Core/Caching/DataCache.swift

import Foundation
import OSLog

// MARK: - DiskCache
public actor DiskCache<Key: Hashable & Sendable>: Caching, @unchecked Sendable {
    public typealias Key = Key
    public typealias Value = Data

    public nonisolated let options: Options
    public nonisolated let logger: Logger

    public subscript (key: Key) -> Data? {
        get async throws {
            try await value(for: key)
        }
//        set {
//            if let newValue {
//                storeData(newValue, for: key)
//            } else {
//                removeData(for: key)
//            }
//        }
    }

    private let clock: any Clock<Duration>

    private var path: URL {
        get throws {
            try _prepare()
            return _path
        }
    }
    private var _path: URL!
    private var prepared = false

    private var queueingTask: Task<Void, Never>?

    private(set) lazy var staging = Staging<Key>()

    private var runningTasks: [Key: Task<Void, Error>] = [:]

    private(set) var flushingTask: Task<Void, Error>?

    private(set) var sweepingTask: Task<Void, Error>?

    private(set) var isFlushNeeded = false

    private(set) var isFlushScheduled = false

    private var logKey: String {
        guard let path = try? path else { return "" }
        return "[\(path.lastPathComponent)] "
    }

    public init(options: Options, clock: some Clock<Duration> = .suspending, logger: Logger = .init(.disabled)) {
        self.options = options
        self.clock = clock
        self.logger = logger
        Task {
            try await _prepare()
        }
    }

    public func prepare() throws {
        try _prepare()
    }

    public func value(for key: Key) async throws -> Data? {
        try await value(for: key, with: Date())
    }

    func value(for key: Key, with now: Date) async throws -> Data? {
        await Task.yield()

        let task = Task<Data?, Error> {
            _ = await queueingTask?.result

            for stage in staging.stages.reversed() {
                if stage.removeAll {
                    return nil
                }
                if let change = stage.changes[key] {
                    switch change.operation {
                    case .add(let data): return data
                    case .remove: return nil
                    }
                }
            }

            guard let url = url(for: key) else { return nil }

            await waitForTask(for: key)

            let task = Task<Data?, Error>.detached {
                do {
                    let data = try Data(contentsOf: url)

                    do {
                        var url = url
                        var meta = URLResourceValues()
                        meta.contentAccessDate = now
                        try url.setResourceValues(meta)
                    } catch {}

                    return data
                } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
                    return nil
                }
            }
            return try await task.value
        }
        return try await task.value
    }


    @discardableResult
    public nonisolated func store(_ value: Value, for key: Key) -> Task<Void, Never> {
        return Task {
            let task = await _store(value, for: key)
            await task.value
        }
    }

    private func _store(_ data: Data, for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            await _storeData(data, for: key)
        }
    }

    @discardableResult
    public nonisolated func remove(for key: Key) -> Task<Void, Never> {
        return Task {
            let task = await _remove(for: key)
            await task.value
        }
    }

    private func _remove(for key: Key) -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            await _removeData(for: key)
        }
    }

    @discardableResult
    public nonisolated func removeAll() -> Task<Void, Never> {
        return Task {
            let task = await _removeAll()
            await task.value
        }
    }

    private func _removeAll() -> Task<Void, Never> {
        queueingTask.enqueueAndReplacing { [weak self] in
            guard let self else { return }
            await _removeDataAll()
        }
    }

    public func url(for key: Key) -> URL? {
        guard let filename = options.filename(key) else { return nil }
        return try? path.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: -
    private func _prepare() throws {
        if prepared {
            return
        }
        prepared = true

        let dir: URL?
        switch options.path {
        case .default(let name):
            dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(name)

        case .custom(let url):
            dir = url
        }
        _path = dir
        scheduleSweep(after: 10)

        if dir == nil {
            throw CocoaError(.fileNoSuchFile)
        }
    }

    private func _storeData(_ data: Data, for key: Key) async {
        logger.debug("\(self.logKey)store data: \(data) for \(String(describing: key))")
        staging.add(data: data, for: key)
        setNeedsFlushChanges()
    }

    private func _removeData(for key: Key) async {
        logger.debug("\(self.logKey)remove data for \(String(describing: key))")
        staging.remove(for: key)
        setNeedsFlushChanges()
    }

    private func _removeDataAll() async {
        logger.debug("\(self.logKey)remove data all")
        staging.removeAll()
        setNeedsFlushChanges()
    }

    private func waitForTask(for key: Key) async {
        guard let task = runningTasks[key] else { return }
        _ = await task.result
    }
}

extension DiskCache {
    private func setNeedsFlushChanges() {
        guard !isFlushNeeded else { return }
        isFlushNeeded = true

        logger.debug("\(self.logKey)flush scheduled")

        let oldTask = flushingTask
        flushingTask = Task {
            try await flushIfNeeded(oldTask)
        }
    }

    private func flushIfNeeded(_ oldTask: Task<Void, Error>?) async throws {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        defer { isFlushScheduled = false }

        try await clock.sleep(for: .seconds(1))
        try? await oldTask?.value

        guard isFlushNeeded else { return }
        isFlushNeeded = false

        logger.debug("\(self.logKey)flush starting")
        await _flushIfNeeded(numberOfAttempts: staging.stages.count)
    }

    private func _flushIfNeeded(numberOfAttempts: Int) async {
        guard numberOfAttempts > 0, let stage = staging.stages.first else { return }
        let changes = await _flush(on: stage)
        staging.flushed(id: stage.id, changes: changes, with: logger, logKey: self.logKey)

        if !staging.stages.isEmpty {
            await _flushIfNeeded(numberOfAttempts: numberOfAttempts - 1)
        }
    }

    private func _flush(on stage: Staging<Key>.Stage) async -> [Staging<Key>.Change] {
        await withTaskGroup(of: [Staging<Key>.Change].self) { group in
            if stage.removeAll {
                let changes = Array(stage.changes.values)
                let task = performChangeRemoveAll(for: changes)
                group.addTask {
                    do {
                        try await task.value
                        return changes
                    } catch {
                        return []
                    }
                }
            } else {
                for change in stage.changes.values {
                    guard let url = url(for: change.key) else {
                        group.addTask { [change] }
                        continue
                    }
                    let task = peformChange(change, with: url)
                    group.addTask {
                        do {
                            try await task.value
                            return [change]
                        } catch {
                            return []
                        }
                    }
                }
            }

            var results: [Staging<Key>.Change] = []
            for await changes in group {
                results.append(contentsOf: changes)
            }
            return results
        }
    }

    private func peformChange(_ change: Staging<Key>.Change, with url: URL) -> Task<Void, Error> {
        let task = Task {
            do {
                switch change.operation {
                case .add(let data):
                    if case let dir = url.deletingLastPathComponent(),
                       !FileManager.default.fileExists(atPath: dir.path) {
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    }

                    logger.debug("\(self.logKey)added data: \(data) to \(url.lastPathComponent)")
                    try data.write(to: url)

                case .remove:
                    logger.debug("\(self.logKey)removed data at \(url.lastPathComponent)")
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                logger.error("\(self.logKey)\(String(describing: error))")
                throw error
            }
        }
        assert(runningTasks[change.key] == nil)
        runningTasks[change.key] = task
        Task {
            _ = await task.result
            runningTasks.removeValue(forKey: change.key)
        }

        return task
    }

    private func performChangeRemoveAll(for changes: some Collection<Staging<Key>.Change>) -> Task<Void, Error> {
        let task = Task {
            do {
                let dir = try path
                try FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("\(self.logKey)\(String(describing: error))")
                throw error
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
}

extension DiskCache {
    private func scheduleSweep(after seconds: Int) {
        logger.debug("\(self.logKey)sweep scheduled")
        let oldTask = sweepingTask
        sweepingTask = Task {
            try await clock.sleep(for: .seconds(seconds))
            _ = await oldTask?.result
            do {
                logger.debug("\(self.logKey)sweep starting")
                try performSweep()
                logger.debug("\(self.logKey)sweep finished")
            } catch {
                logger.error("\(self.logKey)sweep error: \(String(describing: error))")
            }
            scheduleSweep(after: 30)
        }
    }

    private func performSweep() throws {
        var items = try contents(keys: [.contentAccessDateKey, .totalFileAllocatedSizeKey])
        guard !items.isEmpty else { return }

        var size = items.reduce(0) { $0 + ($1.meta.totalFileAllocatedSize ?? 0) }

        @discardableResult
        func removeItem(_ item: Entry) -> Bool {
            do {
                try FileManager.default.removeItem(at: item.url)
                size -= item.meta.totalFileAllocatedSize ?? 0
                logger.debug("\(self.logKey)sweeped item: \(item.url.lastPathComponent), size: \(item.meta.totalFileAllocatedSize ?? 0)")
                return true
            } catch {
                logger.error("\(self.logKey)sweep item: \(item.url.lastPathComponent), error: \(String(describing: error))")
                return false
            }
        }

        if let timeout = options.expirationTimeout {
            let date = Date().addingTimeInterval(-timeout)
            for (i, item) in items.enumerated().reversed() {
                guard let accessDate = item.meta.contentAccessDate, accessDate <= date else { continue }
                if removeItem(item) {
                    items.remove(at: i)
                }
            }
        }

        guard size > options.sizeLimit else { return }
        let sizeLimit = Int(Double(options.sizeLimit) * 0.7)
        items = items.sorted(by: { lhs, rhs in
            (lhs.meta.contentAccessDate ?? .distantPast) > (rhs.meta.contentAccessDate ?? .distantPast)
        })
        while size > sizeLimit, let item = items.popLast() {
            removeItem(item)
        }
    }

    private struct Entry {
        let url: URL
        let meta: Meta

        struct Meta {
            let fileSize: Int?
            let totalFileAllocatedSize: Int?
            let contentAccessDate: Date?

            init(_ meta: URLResourceValues, in keys: Set<URLResourceKey>) {
                fileSize = meta.fileSize
                totalFileAllocatedSize = meta.totalFileAllocatedSize
                contentAccessDate = meta.contentAccessDate
            }
        }
    }

    private func contents(keys: [URLResourceKey] = []) throws -> [Entry] {
        let urls: [URL]
        do {
            urls = try FileManager.default
                .contentsOfDirectory(at: path, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let keys = Set(keys)
        return urls.compactMap { url in
            guard let meta = try? url.resourceValues(forKeys: keys) else { return nil }
            return Entry(url: url, meta: .init(meta, in: keys))
        }
    }

    /// The total number of items in the cache.
    public var totalCount: Int {
        get throws {
            try contents().count
        }
    }

    /// The total file size of items written on disk.
    ///
    /// Uses `URLResourceKey.fileSizeKey` to calculate the size of each entry.
    /// The total allocated size (see `totalAllocatedSize`. on disk might
    /// actually be bigger.
    public var totalSize: Int {
        get throws {
            try contents(keys: [.fileSizeKey]).reduce(0) {
                $0 + ($1.meta.fileSize ?? 0)
            }
        }
    }

    /// The total file allocated size of all the items written on disk.
    ///
    /// Uses `URLResourceKey.totalFileAllocatedSizeKey`.
    public var totalAllocatedSize: Int {
        get throws {
            try contents(keys: [.totalFileAllocatedSizeKey]).reduce(0) {
                $0 + ($1.meta.totalFileAllocatedSize ?? 0)
            }
        }
    }
}

struct Staging<Key: Hashable & Sendable> {
    enum Operation: Equatable {
        case add(Data)
        case remove
    }
    struct Change {
        let key: Key
        let id: Int
        let operation: Operation
    }
    struct Stage {
        let id: Int
        var changes: [Key: Change]
        var removeAll = false
    }

    private(set) var stages: [Stage] = []
    private var stageID = IDGenerator()
    private var changeID = IDGenerator()

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
        var stage = Stage(id: stageID.nextID(), changes: [:], removeAll: true)
        for key in keys {
            stage.changes[key] = Change(key: key, id: changeID.nextID(), operation: .remove)
        }
        stages.append(stage)
    }

    mutating func flushed(id: Int, changes: [Change], with logger: Logger, logKey: @autoclosure @escaping () -> String) {
        guard case (let i, var stage)? = stages.enumerated().first(where: { $1.id == id }) else {
            assert(changes.isEmpty)
            return
        }

        for change in changes {
            guard let c = stage.changes[change.key], c.id == change.id else {
                assertionFailure("maybe invalid state?")
                continue
            }
            stage.changes.removeValue(forKey: c.key)
            logger.debug("\(logKey())flushed change \(String(describing: c.key)), at stage: \(stage.id)")
        }

        if stage.changes.isEmpty {
            stages.remove(at: i)
            logger.debug("\(logKey())flushed stage: \(stage.id), removed")
        } else {
            stages[i] = stage
        }
    }

    private func checkConflicts(on key: Key) -> Bool {
        guard let stage = stages.last else { return true }
        if stage.removeAll { return true }
        if stage.changes.keys.contains(key) { return true }
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
