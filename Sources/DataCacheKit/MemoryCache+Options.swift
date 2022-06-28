import Foundation

extension MemoryCache {
    public struct Options {
        public var countLimit: Int

        var sizeLimit: Int?

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
        sizeLimit: Int
    ) {
        self.countLimit = countLimit
        self.sizeLimit = sizeLimit
    }
}
