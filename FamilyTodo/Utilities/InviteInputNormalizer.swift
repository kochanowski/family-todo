import Foundation

enum InviteInputNormalizationError: LocalizedError {
    case empty
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .empty:
            "Invite link is empty."
        case .invalidFormat:
            "Invite link format is invalid."
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

        if isShortCode(trimmed) {
            return NormalizedInviteInput(
                inviteCode: makeICloudShareURL(fromShortCode: trimmed),
                kind: .shortCode
            )
        }

        throw InviteInputNormalizationError.invalidFormat
    }

    static func normalizedURL(from raw: String) throws -> URL {
        let normalized = try normalize(raw)
        guard let url = URL(string: normalized) else {
            throw InviteInputNormalizationError.invalidFormat
        }
        return url
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

        guard let payloadRaw = payloadFromPath ?? payloadFromQuery,
              !payloadRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InviteInputNormalizationError.invalidFormat
        }

        let decodedPayload = payloadRaw.removingPercentEncoding ?? payloadRaw
        let trimmedPayload = decodedPayload.trimmingCharacters(in: .whitespacesAndNewlines)

        if let urlInvite = normalizeICloudShareURL(trimmedPayload) {
            return NormalizedInviteInput(inviteCode: urlInvite, kind: .customScheme)
        }

        if isShortCode(trimmedPayload) {
            return NormalizedInviteInput(
                inviteCode: makeICloudShareURL(fromShortCode: trimmedPayload),
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

    private static func isShortCode(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 160 else { return false }
        return trimmed.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }
    }

    private static func makeICloudShareURL(fromShortCode shortCode: String) -> String {
        "https://www.icloud.com/share/\(shortCode)"
    }
}
