import XCTest
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

@MainActor
final class DiskCacheTests: XCTestCase {
    private var tmpDir: URL!
    private var numberOfItems: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).count) ?? 0
    }
    private func cacheOptions<T: CustomStringConvertible>() -> DiskCache<T>.Options {
        var options = DiskCache<T>.Options.default(path: .custom(tmpDir))
        options.filename = { $0.description }
        return options
    }

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        print(tmpDir.absoluteString)
        XCTAssertEqual(numberOfItems, 0)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testStoreData() async throws {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock, logger: .init(.default))

        cache.store(Data(), for: "empty")

        try await yield(until: await cache.isFlushScheduled)

        do {
            // load from staging (memory)
            let data = try await cache.value(for: "empty")
            XCTAssertNotNil(data)

            let url = try XCTUnwrap(cache.url(for: "empty"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        } catch {
            XCTFail("\(error)")
        }

        clock.advance(by: .milliseconds(500))
        try? await SuspendingClock().sleep(until: .now.advanced(by: .microseconds(300)))

        XCTAssertEqual(numberOfItems, 0)

        clock.advance(by: .milliseconds(500))
        try? await SuspendingClock().sleep(until: .now.advanced(by: .microseconds(300)))

        XCTAssertEqual(numberOfItems, 1)

        do {
            // load from disk
            let data = try await cache.value(for: "empty")
            XCTAssertNotNil(data)

            let url = try XCTUnwrap(cache.url(for: "empty"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        } catch {
            XCTFail("\(error)")
        }
    }

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
            XCTAssertEqual(count, 2)
        }

        clock.advance(by: .milliseconds(1000))

        try? await cache.flushingTask?.value

        XCTAssertEqual(numberOfItems, 2)
    }


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
            XCTAssertNil(data0)
            XCTAssertEqual(data1, Data([1, 2]))
        } catch {
            XCTFail("\(error)")
        }

        do {
            cache.logger.debug("check staging layers")
            let count = await cache.staging.stages.count
            XCTAssertEqual(count, 2)

            let change0 = await cache.staging.stages.last?.changes["item0"]?.operation
            XCTAssertEqual(change0, .remove)
        }

        clock.advance(by: .milliseconds(1000))

        try? await cache.flushingTask?.value

        XCTAssertEqual(numberOfItems, 1)
    }

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
            XCTAssertEqual(data0, Data([1]))
            XCTAssertEqual(numberOfItems, 1)

            let isEmpty = await cache.staging.stages.isEmpty
            XCTAssertTrue(isEmpty)
        } catch {
            XCTFail("\(error)")
        }

        cache.removeAll()
        try await yield(until: await cache.isFlushScheduled)

        clock.advance(by: .milliseconds(1000))

        do {
            var isEmpty = await cache.staging.stages.isEmpty
            XCTAssertFalse(isEmpty)

            try? await cache.flushingTask?.value
            let data0 = try await cache.value(for: "item0")
            XCTAssertNil(data0)
            XCTAssertEqual(numberOfItems, 0)

            isEmpty = await cache.staging.stages.isEmpty
            XCTAssertTrue(isEmpty)
        } catch {
            XCTFail("\(error)")
        }
    }

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
            XCTAssertEqual(data2, Data([1, 2, 3]))

            XCTAssertEqual(numberOfItems, 3)
        }

        do {
            var item1 = tmpDir.appendingPathComponent("item1")
            var resourceValues = URLResourceValues()
            resourceValues.contentAccessDate = .distantPast
            try item1.setResourceValues(resourceValues)

            cache.logger.debug("check sweeping layers")
            clock.advance(by: .seconds(10))

            try? await cache.sweepingTask?.value

            XCTAssertEqual(numberOfItems, 2)

            let data0 = try? await cache.value(for: "item0")
            let data1 = try? await cache.value(for: "item2")
            XCTAssertEqual(data0, Data([1]))
            XCTAssertEqual(data1, Data([1, 2, 3]))
        } catch {
            XCTFail("\(error)")
        }
    }
}
