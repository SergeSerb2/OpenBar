#if canImport(os)
import Foundation
import Logging
import os

struct OSLogLogHandler: LogHandler {
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .info

    private let label: String
    private let subsystem: String
    private let logger: os.Logger

    init(label: String, subsystem: String) {
        self.label = label
        self.subsystem = subsystem
        let category = Self.category(from: label, subsystem: subsystem)
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get { self.metadata[metadataKey] }
        set { self.metadata[metadataKey] = newValue }
    }

    func log(event: LogEvent) {
        let message = event.message.description
        let metadata = Self.metadataSuffix(metadata: self.metadata, extraMetadata: event.metadata)
        // os.Logger's own mapping: warning is error-level, critical is a fault.
        let type: OSLogType = switch event.level {
        case .trace, .debug: .debug
        case .info, .notice: .info
        case .warning, .error: .error
        case .critical: .fault
        }
        // Messages are redacted before they reach this handler and stay readable in `log show`. Metadata mostly
        // carries provider-derived values (response bodies, URLs, identifiers), so the unified log keeps it
        // private; the opt-in file log still records the redacted values for diagnostics.
        if let metadata {
            self.logger.log(level: type, "\(message, privacy: .public) (\(metadata, privacy: .private))")
        } else {
            self.logger.log(level: type, "\(message, privacy: .public)")
        }
    }

    private static func category(from label: String, subsystem: String) -> String {
        let prefix = subsystem + "."
        guard label.hasPrefix(prefix) else { return label }
        return String(label.dropFirst(prefix.count))
    }

    private static func metadataSuffix(
        metadata: Logging.Logger.Metadata,
        extraMetadata: Logging.Logger.Metadata?)
        -> String?
    {
        var merged = metadata
        if let extraMetadata { merged.merge(extraMetadata, uniquingKeysWith: { _, new in new }) }
        guard !merged.isEmpty else { return nil }

        return merged
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}
#endif
