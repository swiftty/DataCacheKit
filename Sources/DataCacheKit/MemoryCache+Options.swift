import Foundation
import OSLog

extension MemoryCache {
    public struct Options {
        public var countLimit: Int
        public var logger: Logger

        var costLimit: Int?

        public init(
            countLimit: Int,
            logger: Logger = .init(.disabled)
        ) {
            self.countLimit = countLimit
            self.logger = logger
        }
    }
}

extension MemoryCache.Options where Value == Data {
    public init(
        countLimit: Int,
        costLimit: Int,
        logger: Logger = .init(.disabled)
    ) {
        self.countLimit = countLimit
        self.costLimit = costLimit
        self.logger = logger
    }
}
