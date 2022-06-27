import XCTest
@testable import DataCacheKit

@discardableResult
func yield(until condition: @autoclosure () async -> Bool, limit: Int = 10000) async -> Bool {
    var limit = limit
    while limit > 0 {
        limit -= 1
        await Task.yield()
        if await condition() {
            return true
        }
    }
    return false
}

final class DiskCacheTests: XCTestCase {
    private var tmpDir: URL!
    private var numberOfItems: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).count) ?? 0
    }
    private func cacheOptions<T: CustomStringConvertible>() -> DiskCache<T>.Options {
        var options = DiskCache<T>.Options.default()
        options.path = tmpDir
        options.filename = { $0.description }
        options.logger = .init(.default)
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
    func testStoreData() async {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock)

        await cache.storeData(Data(), for: "empty").value

        do {
            // load from staging (memory)
            let change = await cache.staging.changes(for: "empty")
            XCTAssertNotNil(change)

            let url = try XCTUnwrap(cache.url(for: "empty"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

            let data = try await cache.cachedData(for: "empty")
            XCTAssertNotNil(data)
        } catch {
            XCTFail("\(error)")
        }

        clock.advance(by: .milliseconds(500))

        do {
            let result = await yield(until: await cache.staging.changes(for: "empty") == nil)
            XCTAssertFalse(result)
        }

        XCTAssertEqual(numberOfItems, 0)

        clock.advance(by: .milliseconds(500))

        do {
            let result = await yield(until: await cache.staging.changes(for: "empty") == nil)
            XCTAssertTrue(result)
        }

        XCTAssertEqual(numberOfItems, 1)

        do {
            // load from disk
            let url = try XCTUnwrap(cache.url(for: "empty"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

            let data = try await cache.cachedData(for: "empty")
            XCTAssertNotNil(data)
        } catch {
            XCTFail("\(error)")
        }
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testStoreDataMultiple() async {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock)

        cache.storeData(Data([1]), for: "item0")
        await cache.storeData(Data([1, 2]), for: "item1").value

        do {
            cache.options.logger.debug("check staging items")
            let count = await cache.staging.stages.first?.changes.count
            XCTAssertEqual(count, 2)
        }

        clock.advance(by: .milliseconds(1000))

        do {
            let result = await yield(until: await cache.staging.stages.isEmpty)
            XCTAssertTrue(result)
        }

        XCTAssertEqual(numberOfItems, 2)
    }


    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testRemoveData() async {
        let clock = ManualClock()
        let cache = DiskCache<String>(options: cacheOptions(), clock: clock)

        cache.storeData(Data([1]), for: "item0")
        cache.storeData(Data([1, 2]), for: "item1")
        await cache.removeData(for: "item0").value

        do {
            let data0 = try await cache.cachedData(for: "item0")
            let data1 = try await cache.cachedData(for: "item1")
            XCTAssertNil(data0)
            XCTAssertEqual(data1, Data([1, 2]))
        } catch {
            XCTFail("\(error)")
        }

        do {
            cache.options.logger.debug("check staging layers")
            let count = await cache.staging.stages.count
            XCTAssertEqual(count, 2)

            let change0 = await cache.staging.stages.last?.changes["item0"]?.operation
            XCTAssertEqual(change0, .remove)
        }

        clock.advance(by: .milliseconds(1000))

        do {
            let result = await yield(until: await cache.staging.stages.isEmpty)
            XCTAssertTrue(result)
        }

        XCTAssertEqual(numberOfItems, 1)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testSweep() async {
        let allocationUnit = 4096

        var options = cacheOptions() as DiskCache<String>.Options
        options.sizeLimit = 3 * allocationUnit - 1
        let clock = ManualClock()
        let cache = DiskCache<String>(options: options, clock: clock)

        cache.storeData(Data([1]), for: "item0")
        cache.storeData(Data([1, 2]), for: "item1")
        await cache.storeData(Data([1, 2, 3]), for: "item2").value

        do {
            cache.options.logger.debug("check staging layers")
            clock.advance(by: .milliseconds(1000))

            let data2 = try? await cache.cachedData(for: "item2")
            XCTAssertEqual(data2, Data([1, 2, 3]))

            try? await cache.flushingTask?.value

            XCTAssertEqual(numberOfItems, 3)
        }

        do {
            var item1 = tmpDir.appendingPathComponent("item1")
            var resourceValues = URLResourceValues()
            resourceValues.contentAccessDate = .distantPast
            try item1.setResourceValues(resourceValues)

            cache.options.logger.debug("check sweeping layers")
            clock.advance(by: .seconds(10))

            try? await cache.sweepingTask?.value

            XCTAssertEqual(numberOfItems, 2)

            let data0 = try? await cache.cachedData(for: "item0")
            let data1 = try? await cache.cachedData(for: "item2")
            XCTAssertEqual(data0, Data([1]))
            XCTAssertEqual(data1, Data([1, 2, 3]))
        } catch {
            XCTFail("\(error)")
        }
    }
}
