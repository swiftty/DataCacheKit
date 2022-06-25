import XCTest
@testable import DataCacheKit

@discardableResult
func yield(until condition: @autoclosure () async -> Bool, limit: Int = 500) async -> Bool {
    var limit = limit
    while limit > 0 {
        limit -= 1
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return false
}

final class DiskCacheTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        print(tmpDir.absoluteString)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        try? FileManager.default.removeItem(at: tmpDir)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    func testStoreData() async {
        let clock = ManualClock()

        var numberOfItems: Int {
            (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path).count) ?? 0
        }
        var options = DiskCache<String>.Options.default()
        options.path = tmpDir
        options.logger = .init(.default)
        let cache = DiskCache<String>(options: options, clock: clock)


        XCTAssertEqual(numberOfItems, 0)
        await cache.storeData(Data(), for: "empty").value

        do {
            // load from staging (memory)
            let change = await cache.staging.changes["empty"]
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
            let result = await yield(until: await cache.staging.changes["empty"] == nil)
            XCTAssertFalse(result)
        }

        XCTAssertEqual(numberOfItems, 0)

        clock.advance(by: .milliseconds(500))

        do {
            let result = await yield(until: await cache.staging.changes["empty"] == nil)
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
}
