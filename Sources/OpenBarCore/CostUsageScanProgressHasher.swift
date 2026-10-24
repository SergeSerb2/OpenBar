#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Progress keys cross process boundaries and must not use Swift's per-process hash seed.
struct CostUsageScanProgressHasher {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private var hash = SHA256()
    private var failed = false

    mutating func combine(_ value: some Encodable) {
        guard let data = try? self.encoder.encode(value) else {
            self.failed = true
            return
        }
        self.hash.update(data: data)
        self.hash.update(data: Data([0]))
    }

    mutating func finalize() -> String {
        self.failed ? "unavailable" : self.hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
