import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum OpenBarConfigStoreError: LocalizedError {
    case invalidURL
    case decodeFailed(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid OpenBar config path."
        case let .decodeFailed(details):
            "Failed to decode OpenBar config: \(details)"
        case let .encodeFailed(details):
            "Failed to encode OpenBar config: \(details)"
        }
    }
}

public struct OpenBarConfigStore: @unchecked Sendable {
    public static let pathEnvironmentKey = "OPENBAR_CONFIG"
    public static let xdgConfigHomeEnvironmentKey = "XDG_CONFIG_HOME"

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> OpenBarConfig? {
        try self.load(migratingLegacySecrets: true)
    }

    private func load(migratingLegacySecrets: Bool) throws -> OpenBarConfig? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        let data = try Data(contentsOf: self.fileURL)
        guard !data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) else { return nil }
        do {
            let decoded = try OpenBarConfig.decode(from: data)
            let normalized = decoded.normalized()
            // Provider normalizers may move a legacy credential out of the public region field.
            let movedLegacySecret = decoded.providers.contains { original in
                guard original.region != nil,
                      let current = normalized.providerConfig(for: original.id), current.region == nil,
                      let provider = original.id.firstPartyProvider
                else { return false }
                return ProviderDescriptorRegistry.descriptor(for: provider).credentials?.usesSecretKey == true
            }
            guard migratingLegacySecrets, movedLegacySecret else { return normalized }
            var migrated: OpenBarConfig?
            try self.withWriteLock {
                // Read again under the write lock so migration cannot replace a newer credential.
                migrated = try self.load(migratingLegacySecrets: false)
                if let migrated {
                    try CredentialFileWriter.writePrivate(self.encodedData(for: migrated), to: self.fileURL)
                }
            }
            return migrated
        } catch {
            throw OpenBarConfigStoreError.decodeFailed(error.localizedDescription)
        }
    }

    public func loadOrCreateDefault() throws -> OpenBarConfig {
        if let existing = try self.load() {
            return existing
        }
        return try self.update { _ in }
    }

    /// Serialize the entire read-modify-write across processes, then publish atomically.
    @discardableResult
    public func update(_ update: (inout OpenBarConfig) throws -> Void) throws -> OpenBarConfig {
        try self.withTransaction { existing, publish in
            var config = existing ?? .makeDefault()
            try update(&config)
            try publish(config)
            return config
        }
    }

    /// Legacy migration also needs to defer cleanup until publication succeeds, under the same lock.
    package func withTransaction<T>(
        _ operation: (OpenBarConfig?, (OpenBarConfig) throws -> Void) throws -> T) throws -> T
    {
        var result: T?
        try self.withWriteLock {
            result = try operation(self.load()) { config in
                try CredentialFileWriter.writePrivate(self.encodedData(for: config), to: self.fileURL)
            }
        }
        guard let result else { throw POSIXError(.EIO) }
        return result
    }

    public func save(_ config: OpenBarConfig) throws {
        let data = try self.encodedData(for: config)
        try self.saveEncodedData(data)
    }

    public func encodedData(for config: OpenBarConfig) throws -> Data {
        guard config.version == OpenBarConfig.currentVersion else {
            throw OpenBarConfigStoreError.encodeFailed("Unsupported config version \(config.version).")
        }
        do {
            return try config.normalized().encodedData()
        } catch {
            throw OpenBarConfigStoreError.encodeFailed(error.localizedDescription)
        }
    }

    public func saveEncodedData(_ data: Data) throws {
        try self.saveEncodedData(data, beforePublish: {})
    }

    /// App writers can revalidate a snapshot after staging, while still holding the file lock.
    package func saveEncodedData(_ data: Data, beforePublish: @escaping () throws -> Void) throws {
        try self.withWriteLock {
            try CredentialFileWriter.writePrivate(data, to: self.fileURL) { _ in
                try beforePublish()
            }
        }
    }

    /// Best-effort refreshes must compare and publish under the same lock as ordinary config writes.
    /// Skip contention rather than delaying an interactive writer or publishing a stale credential.
    package func updateIfAvailable(_ update: (inout OpenBarConfig) throws -> Bool) throws {
        try self.withWriteLock(wait: false) {
            guard var config = try self.load(migratingLegacySecrets: false), try update(&config) else { return }
            try CredentialFileWriter.writePrivate(self.encodedData(for: config), to: self.fileURL)
        }
    }

    public func deleteIfPresent() throws {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return }
        try self.withWriteLock {
            if self.fileManager.fileExists(atPath: self.fileURL.path) {
                try self.fileManager.removeItem(at: self.fileURL)
            }
        }
    }

    private func withWriteLock(wait: Bool = true, _ body: () throws -> Void) throws {
        try self.fileManager.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        // Keep this inode: unlinking the lock could give simultaneous writers different locks.
        let descriptor = open(
            self.fileURL.appendingPathExtension("lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_uid == geteuid()
        else { throw POSIXError(.EINVAL) }
        while flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0 {
            if errno == EINTR { continue }
            if !wait, errno == EWOULDBLOCK { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        try body()
    }

    public static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> URL
    {
        if let override = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }

        if let xdgConfigHome = environment[xdgConfigHomeEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !xdgConfigHome.isEmpty
        {
            let expanded = (xdgConfigHome as NSString).expandingTildeInPath
            if (expanded as NSString).isAbsolutePath {
                return URL(fileURLWithPath: expanded, isDirectory: true)
                    .appendingPathComponent("openbar", isDirectory: true)
                    .appendingPathComponent("config.json")
            }
        }

        let xdgDefault = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("openbar", isDirectory: true)
            .appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: xdgDefault.path) {
            return xdgDefault
        }

        let legacy = home
            .appendingPathComponent(".openbar", isDirectory: true)
            .appendingPathComponent("config.json")
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }

        return xdgDefault
    }
}
