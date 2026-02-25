import Foundation

enum InviteInputNormalizationError: LocalizedError {
    case empty
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Invite link is empty."
        case .invalidFormat:
            return "Invite link format is invalid."
        }
    }
}

struct InviteInputNormalizer {
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InviteInputNormalizationError.empty
        }

        // Common manual input patterns:
        // - full URL: https://www.icloud.com/share/...
        // - missing scheme: www.icloud.com/share/... or icloud.com/share/...
        let lowered = trimmed.lowercased()
        let normalizedCandidate: String
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            normalizedCandidate = trimmed
        } else if lowered.hasPrefix("www.icloud.com/share/") || lowered.hasPrefix("icloud.com/share/") {
            normalizedCandidate = "https://\(trimmed)"
        } else if lowered.contains("icloud.com/share/") {
            normalizedCandidate = "https://\(trimmed)"
        } else {
            throw InviteInputNormalizationError.invalidFormat
        }

        guard let components = URLComponents(string: normalizedCandidate),
              let scheme = components.scheme,
              (scheme == "http" || scheme == "https"),
              components.host != nil,
              let url = components.url
        else {
            throw InviteInputNormalizationError.invalidFormat
        }

        return url.absoluteString
    }

    static func normalizedURL(from raw: String) throws -> URL {
        let normalized = try normalize(raw)
        guard let url = URL(string: normalized) else {
            throw InviteInputNormalizationError.invalidFormat
        }
        return url
    }
}
