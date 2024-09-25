import Testing
import Foundation
@testable import DataCacheKit

func yield(until condition: @autoclosure () async -> Bool, message: @autoclosure () -> String? = nil, limit: Int = 10000) async throws {
    var limit = limit
    while limit > 0 {
        limit -= 1
        await Task.yield()
        if await condition() {
            return
        }
    }
    struct E: LocalizedError {
        var errorDescription: String?
    }
    throw E(errorDescription: message())
}

final class DiskCacheTests {
    private var tmpDir: URL!
    private var numberOfItems: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).count) ?? 0
    }
    private func cacheOptions<T: CustomStringConvertible>() -> DiskCache<T>.Options {
        var options = DiskCache<T>.Options.default(path: .custom(tmpDir))
        options.filename = { $0.description }
        return options
    }

    init() async throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        print(tmpDir.absoluteString)
        #expect(numberOfItems == 0)
    }

    deinit {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testStoreData() async throws {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock, logger: .init(.default))

        cache.store(Data(), for: "empty")

        try await yield(until: await cache.isFlushScheduled)

        do {
            // load from staging (memory)
            let data = try await cache.value(for: "empty")
            #expect(data != nil)

            let url = try #require(cache.url(for: "empty"))
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        clock.advance(by: .milliseconds(500))

        #expect(numberOfItems == 0)

        clock.advance(by: .milliseconds(500))

        try await yield(until: await !cache.isFlushScheduled)

        #expect(numberOfItems == 1)

        do {
            // load from disk
            let data = try await cache.value(for: "empty")
            #expect(data != nil)

            let url = try #require(cache.url(for: "empty"))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testStoreDataMultiple() async throws {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock, logger: .init(.default))

        cache.store(Data([1]), for: "item0")
        cache.store(Data([1, 2]), for: "item1")

        try await yield(until: await cache.isFlushScheduled)

        do {
            cache.logger.debug("check staging items")
            let count = await cache.staging.stages.first?.changes.count
            #expect(count == 2)
        }

        clock.advance(by: .milliseconds(1000))

        try? await cache.flushingTask?.value

        #expect(numberOfItems == 2)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testRemoveData() async throws {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock, logger: .init(.default))

        cache.store(Data([1]), for: "item0")
        cache.store(Data([1, 2]), for: "item1")
        cache.remove(for: "item0")

        try await yield(until: await cache.isFlushScheduled)

        do {
            let data0 = try await cache.value(for: "item0")
            let data1 = try await cache.value(for: "item1")
            #expect(data0 == nil)
            #expect(data1 == Data([1, 2]))
        }

        do {
            cache.logger.debug("check staging layers")
            let count = await cache.staging.stages.count
            #expect(count == 2)

            let change0 = await cache.staging.stages.last?.changes["item0"]?.operation
            #expect(change0 == .remove)
        }

        clock.advance(by: .milliseconds(1000))

        try? await cache.flushingTask?.value

        #expect(numberOfItems == 1)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testRemoveDataAll() async throws {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock, logger: .init(.default))

        cache.store(Data([1]), for: "item0")
        try await yield(until: await cache.isFlushScheduled)

        clock.advance(by: .milliseconds(1000))

        do {
            try? await cache.flushingTask?.value
            let data0 = try await cache.value(for: "item0")
            #expect(data0 == Data([1]))
            #expect(numberOfItems == 1)

            let isEmpty = await cache.staging.stages.isEmpty
            #expect(isEmpty)
        }

        cache.removeAll()
        try await yield(until: await cache.isFlushScheduled)

        clock.advance(by: .milliseconds(1000))

        do {
            var isEmpty = await cache.staging.stages.isEmpty
            #expect(!isEmpty)

            try? await cache.flushingTask?.value
            let data0 = try await cache.value(for: "item0")
            #expect(data0 == nil)
            #expect(numberOfItems == 0)

            isEmpty = await cache.staging.stages.isEmpty
            #expect(isEmpty)
        }
    }

    @Test
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testSweep() async throws {
        let allocationUnit = 4096

        var options = cacheOptions() as DiskCache<String>.Options
        options.sizeLimit = 3 * allocationUnit - 1
        let clock = ManualClock()
        let cache = DiskCache<String>(options: options, clock: clock)

        cache.store(Data([1]), for: "item0")
        cache.store(Data([1, 2]), for: "item1")
        cache.store(Data([1, 2, 3]), for: "item2")

        try await yield(until: await cache.isFlushScheduled)

        do {
            cache.logger.debug("check staging layers")
            clock.advance(by: .milliseconds(1000))

            try? await cache.flushingTask?.value

            let data2 = try? await cache.value(for: "item2")
            #expect(data2 == Data([1, 2, 3]))

            #expect(numberOfItems == 3)
        }

        do {
            var item1 = tmpDir.appendingPathComponent("item1")
            var resourceValues = URLResourceValues()
            resourceValues.contentAccessDate = .distantPast
            try item1.setResourceValues(resourceValues)

            cache.logger.debug("check sweeping layers")
            clock.advance(by: .seconds(10))

            try? await cache.sweepingTask?.value

            #expect(numberOfItems == 2)

            let data0 = try? await cache.value(for: "item0")
            let data1 = try? await cache.value(for: "item2")
            #expect(data0 == Data([1]))
            #expect(data1 == Data([1, 2, 3]))
        }
    }
}
