import CloudKit
import Foundation

actor CloudKitChangeTokenStore {
    private let userDefaults: UserDefaults
    private let zoneTokenDefaultsKey = "CloudKit.zoneChangeTokens.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func zoneToken(
        scope: CloudKitManager.HouseholdDatabaseScope,
        zoneID: CKRecordZone.ID
    ) -> CKServerChangeToken? {
        guard let raw = storedZoneTokens()[storageKey(scope: scope, zoneID: zoneID)] else {
            return nil
        }

        guard let data = Data(base64Encoded: raw) else {
            return nil
        }

        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self,
            from: data
        )
    }

    func setZoneToken(
        _ token: CKServerChangeToken?,
        scope: CloudKitManager.HouseholdDatabaseScope,
        zoneID: CKRecordZone.ID
    ) {
        var tokens = storedZoneTokens()
        let key = storageKey(scope: scope, zoneID: zoneID)

        if let token,
           let data = try? NSKeyedArchiver.archivedData(
               withRootObject: token,
               requiringSecureCoding: true
           )
        {
            tokens[key] = data.base64EncodedString()
        } else {
            tokens.removeValue(forKey: key)
        }

        userDefaults.set(tokens, forKey: zoneTokenDefaultsKey)
    }

    private func storedZoneTokens() -> [String: String] {
        (userDefaults.dictionary(forKey: zoneTokenDefaultsKey) as? [String: String]) ?? [:]
    }

    private func storageKey(
        scope: CloudKitManager.HouseholdDatabaseScope,
        zoneID: CKRecordZone.ID
    ) -> String {
        let scopeComponent = switch scope {
        case .ownerPrivate:
            "ownerPrivate"
        case .participantShared:
            "participantShared"
        }

        return "\(scopeComponent)|\(zoneID.zoneName)|\(zoneID.ownerName)"
    }
}
