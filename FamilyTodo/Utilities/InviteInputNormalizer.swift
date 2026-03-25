import Foundation

enum InviteInputNormalizationError: LocalizedError {
    case empty
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .empty:
            "Invite input is empty."
        case .invalidFormat:
            "Invite format is invalid."
        }
    }
}

enum InviteInputKind: Equatable {
    case iCloudURL
    case customScheme
    case shortCode
}

struct NormalizedInviteInput: Equatable {
    let inviteCode: String
    let kind: InviteInputKind

    var requiresConfirmation: Bool {
        kind == .customScheme
    }
}

enum InviteInputNormalizer {
    static let preferredInviteCodeLength = 6
    static let legacyInviteCodeLength = 8
    static let maximumInviteCodeLength = max(preferredInviteCodeLength, legacyInviteCodeLength)

    static func normalize(_ raw: String) throws -> String {
        try normalizeInput(raw).inviteCode
    }

    static func normalizeInput(_ raw: String) throws -> NormalizedInviteInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InviteInputNormalizationError.empty
        }

        if let customInvite = try normalizeCustomSchemeIfNeeded(trimmed) {
            return customInvite
        }

        if let urlInvite = normalizeICloudShareURL(trimmed) {
            return NormalizedInviteInput(inviteCode: urlInvite, kind: .iCloudURL)
        }

        if let normalizedCode = normalizeInviteCodeToken(trimmed) {
            return NormalizedInviteInput(
                inviteCode: normalizedCode,
                kind: .shortCode
            )
        }

        throw InviteInputNormalizationError.invalidFormat
    }

    static func normalizedURL(from raw: String) throws -> URL {
        let normalized = try normalize(raw)
        guard let urlString = normalizeICloudShareURL(normalized),
              let url = URL(string: urlString)
        else {
            throw InviteInputNormalizationError.invalidFormat
        }
        return url
    }

    static func normalizeInviteCodeToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let supportedLengths = [preferredInviteCodeLength, legacyInviteCodeLength]
        guard supportedLengths.contains(trimmed.count) else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func normalizeCustomSchemeIfNeeded(_ input: String) throws -> NormalizedInviteInput? {
        guard let components = URLComponents(string: input),
              components.scheme?.lowercased() == "housepulse"
        else {
            return nil
        }

        let host = components.host?.lowercased()
        let path = components.path
        let pathComponents = path.split(separator: "/").map(String.init)

        let payloadFromPath: String?
        if host == "join" {
            let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            payloadFromPath = trimmedPath.isEmpty ? nil : trimmedPath
        } else if pathComponents.first?.lowercased() == "join", pathComponents.count > 1 {
            payloadFromPath = pathComponents.dropFirst().joined(separator: "/")
        } else {
            payloadFromPath = nil
        }

        let payloadFromQuery = components.queryItems?.first(where: {
            let name = $0.name.lowercased()
            return name == "code" || name == "invite"
        })?.value
        let payloadFromEncodedURL = components.queryItems?.first(where: {
            let name = $0.name.lowercased()
            return name == "u" || name == "shareurl"
        })?.value

        let decodedURLPayload = payloadFromEncodedURL.flatMap(decodeBase64URLPayload)

        guard let payloadRaw = payloadFromPath ?? payloadFromQuery ?? decodedURLPayload,
              !payloadRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InviteInputNormalizationError.invalidFormat
        }

        let decodedPayload = payloadRaw.removingPercentEncoding ?? payloadRaw
        let trimmedPayload = decodedPayload.trimmingCharacters(in: .whitespacesAndNewlines)

        if let urlInvite = normalizeICloudShareURL(trimmedPayload) {
            return NormalizedInviteInput(inviteCode: urlInvite, kind: .customScheme)
        }

        if let normalizedCode = normalizeInviteCodeToken(trimmedPayload) {
            return NormalizedInviteInput(
                inviteCode: normalizedCode,
                kind: .customScheme
            )
        }

        throw InviteInputNormalizationError.invalidFormat
    }

    private static func normalizeICloudShareURL(_ input: String) -> String? {
        let lowered = input.lowercased()
        let candidate: String
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            candidate = input
        } else if lowered.hasPrefix("www.icloud.com/share/") || lowered.hasPrefix("icloud.com/share/") {
            candidate = "https://\(input)"
        } else {
            return nil
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host.contains("icloud.com"),
              components.path.lowercased().hasPrefix("/share/"),
              let url = components.url
        else {
            return nil
        }

        return url.absoluteString
    }

    private static func decodeBase64URLPayload(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var base64 = trimmed
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }

        guard
            let data = Data(base64Encoded: base64),
            let decoded = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !decoded.isEmpty
        else {
            return nil
        }

        return decoded
    }
}
