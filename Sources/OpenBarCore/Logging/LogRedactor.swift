import Foundation

public enum LogRedactor {
    private static let fallbackRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "$^", options: [])
        } catch {
            fatalError("Failed to build fallback regex: \(error)")
        }
    }()

    /// Credential names: `x-api-key`, `OPENAI_API_KEY`, `access_token`, `refreshToken`, `client_secret`, ...
    /// The prefix is bounded so a long `a-b-c-…` run cannot make the match quadratic.
    private static let credentialName =
        #"(?:[a-z0-9]+[_-]){0,4}(?:api[_-]?(?:key|token)|(?:access|refresh|id|auth|oauth)[_-]?token|"#
            + #"client[_-]?secret|session[_-]?(?:key|token)|password)"#

    /// Starts only at the beginning of a run, so long `@`-free runs stay linear now that more lines are scanned.
    private static let emailRegex = Self.makeRegex(
        pattern: #"(?<![A-Z0-9._%+-])[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive])
    private static let cookieHeaderRegex = Self.makeRegex(
        pattern: #"(?i)(cookie\s*:\s*)([^\r\n]+)"#)
    private static let authorizationRegex = Self.makeRegex(
        pattern: #"(?i)(authorization\s*:\s*)([^\r\n]+)"#)
    /// Bearer tokens may be base64 or base64url, so `/`, `+`, `~`, and `=` belong to the token.
    private static let bearerRegex = Self.makeRegex(
        pattern: #"(?i)\bbearer\s+[a-z0-9._~+/=\-]+"#)
    private static let minimaxCodingPlanTokenRegex = Self.makeRegex(
        pattern: #"sk-cp-[^\s"'`;,)>\]]+"#)
    private static let minimaxApiTokenRegex = Self.makeRegex(
        pattern: #"sk-api-[^\s"'`;,)>\]]+"#)
    /// Key formats that are secret wherever they appear: `sk-…` (OpenAI, Anthropic), Google `AIza…`, GitHub, xAI.
    private static let apiKeyRegex = Self.makeRegex(
        pattern: #"\b(?:sk-[A-Za-z0-9_\-]{8,}|AIza[0-9A-Za-z_\-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|"#
            + #"github_pat_[A-Za-z0-9_]{20,}|xai-[A-Za-z0-9]{20,})"#)
    private static let jwtRegex = Self.makeRegex(
        pattern: #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*"#)
    /// JSON string fields with a credential name, including generic `token`, `secret`, and auth header names.
    private static let jsonCredentialRegex = Self.makeRegex(
        pattern: #"(?i)("(?:"# + Self.credentialName + #"|token|secret|authorization|cookie|x-api-key)"\s*:\s*")"#
            + #"(?:[^"\\]|\\.)*""#)
    /// Header lines, environment assignments, form or query fields, and escaped JSON:
    /// `x-api-key: …`, `OPENAI_API_KEY=…`, `refresh_token=…`, `\"access_token\":\"…\"`.
    private static let credentialFieldRegex = Self.makeRegex(
        pattern: #"(?i)\b("# + Self.credentialName + #")((?:\\?")?\s*[:=]\s*(?:\\?")?)[^\s"'&,;<>\\]+"#)
    /// Generic names carry credentials as URL query parameters (`?key=`, `&token=`), not in prose.
    private static let queryCredentialRegex = Self.makeRegex(
        pattern: #"(?i)([?&](?:key|token|secret|sig|signature)=)[^&\s"'#<>]+"#)
    private static let sensitiveHintRegex = Self.makeRegex(
        pattern: #"(?i)@|bearer|cookie|authorization|sk-|key|token|secret|passw|aiza|gh[pousr]_|github_pat_|"#
            + #"xai-|eyj|sig"#)

    public static func redact(_ text: String) -> String {
        guard self.mayContainSensitiveValue(text) else { return text }

        var output = text
        // Email is broad and safe first
        output = self.replace(self.emailRegex, in: output, with: "<redacted-email>")
        // MiniMax tokens before broader rules catch them
        output = self.replace(self.minimaxCodingPlanTokenRegex, in: output, with: "<redacted-minimax-token>")
        output = self.replace(self.minimaxApiTokenRegex, in: output, with: "<redacted-minimax-token>")
        // Named fields keep their names, so diagnostics still show which credential was present.
        output = self.replace(self.jsonCredentialRegex, in: output, with: "$1<redacted>\"")
        output = self.replace(self.credentialFieldRegex, in: output, with: "$1$2<redacted>")
        output = self.replace(self.queryCredentialRegex, in: output, with: "$1<redacted>")
        output = self.replace(self.apiKeyRegex, in: output, with: "<redacted-key>")
        output = self.replace(self.jwtRegex, in: output, with: "<redacted-jwt>")
        // Bearer catches "bearer <token>" before authorization wraps it
        output = self.replace(self.bearerRegex, in: output, with: "Bearer <redacted>")
        // Authorization catches the rest (already-redacted content)
        output = self.replace(self.cookieHeaderRegex, in: output, with: "$1<redacted>")
        output = self.replace(self.authorizationRegex, in: output, with: "$1<redacted>")
        return output
    }

    private static func mayContainSensitiveValue(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return self.sensitiveHintRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func makeRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: pattern, options: options)) ?? self.fallbackRegex
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
