import Foundation

/// The process command and working directory needed to resolve a live Pi-family session store.
public struct PiSessionProcessContext: Equatable, Sendable, Codable {
    public let command: String
    /// Original argv when available; this preserves whitespace inside flag values.
    public let arguments: [String]?
    /// The process CWD, when it could be read. An absolute `--session-dir` remains resolvable when this is nil.
    public let workingDirectory: URL?
    /// Captured Pi root selectors only. Missing evidence must never inherit the scanner's environment.
    @ProcessEnvironment public private(set) var selectorEnvironment: [String: String]?

    public init(
        command: String,
        arguments: [String]? = nil,
        workingDirectory: URL?,
        selectorEnvironment: [String: String]? = nil)
    {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory?.standardizedFileURL
        self.selectorEnvironment = PiProcessEnvironment.filtered(selectorEnvironment)
    }
}

extension PiSessionProcessContext {
    private enum CodingKeys: String, CodingKey { case command, arguments, workingDirectory, selectorEnvironment }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            command: container.decode(String.self, forKey: .command),
            arguments: container.decodeIfPresent([String].self, forKey: .arguments),
            workingDirectory: container.decodeIfPresent(URL.self, forKey: .workingDirectory),
            selectorEnvironment: container.decodeIfPresent([String: String].self, forKey: .selectorEnvironment))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.command, forKey: .command)
        try container.encodeIfPresent(self.arguments, forKey: .arguments)
        try container.encodeIfPresent(self.workingDirectory, forKey: .workingDirectory)
        try container.encodeIfPresent(self.selectorEnvironment, forKey: .selectorEnvironment)
    }
}
