import Foundation
import CommonCrypto
import OSLog

extension DiskCache {
    public struct Options {
        public var sizeLimit: Int
        public var filename: @Sendable (Key) -> String?
        public var path: Path
        public var logger: Logger

        public enum Path {
            case `default`(name: String)
            case custom(URL)
        }

        public static func `default`(path: Path) -> Self where Key: CustomStringConvertible {
            self.init(
                sizeLimit: 150 * 1024 * 1024,
                filename: defaultFilename(for:),
                path: path
            )
        }

        public init(
            sizeLimit: Int,
            filename: @escaping @Sendable (Key) -> String?,
            path: Path,
            logger: Logger = .init(.disabled)
        ) {
            self.sizeLimit = sizeLimit
            self.filename = filename
            self.path = path
            self.logger = logger
        }

        @Sendable
        public static func defaultFilename(for key: Key) -> String? where Key: CustomStringConvertible {
            let str = key.description
            guard !str.isEmpty, let data = str.data(using: .utf8) else { return nil }

            let hash = data.withUnsafeBytes { bytes in
                var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
                return hash
            }

            return hash.map { String(format: "%02x", $0) }.joined()
        }
    }
}
