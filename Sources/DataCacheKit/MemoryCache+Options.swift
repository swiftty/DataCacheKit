import Foundation

extension MemoryCache {
    public struct Options {
        public var countLimit: Int

        var costLimit: Int?

        public init(
            countLimit: Int
        ) {
            self.countLimit = countLimit
        }
    }
}

extension MemoryCache.Options where Value == Data {
    public init(
        countLimit: Int,
        costLimit: Int
    ) {
        self.countLimit = countLimit
        self.costLimit = costLimit
    }
}
