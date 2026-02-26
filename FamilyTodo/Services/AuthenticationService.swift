import CloudKit
import Foundation

#if !CI
import AuthenticationServices
import UIKit
#endif

enum AuthDiagnosticStage: String, Codable {
    case cloudKitContainerInit
    case startupStatusCheck
    case signInTapped
    case authorizationReceived
    case authorizationCancelled
    case cloudKitUserFetch
    case signInFailed
}

enum CloudKitAvailabilityReason: String, Codable {
    case enabled
    case disabledByFlag
    case missingKey
    case parseFailure
}

enum AuthMappedErrorCategory: String, Codable {
    case notAuthenticated
    case missingEntitlement
    case badContainer
    case permissionFailure
    case cloudKitNotAvailable
    case authorizationCancelled
    case authorizationFailed
    case genericFailure
}

struct AuthDiagnosticEntry: Codable {
    let timestampISO8601: String
    let stage: AuthDiagnosticStage
    let state: String
    let errorSummary: String?
}

struct AuthDiagnosticsSnapshot: Codable {
    let timestampISO8601: String
    let appVersion: String
    let appBuild: String
    let bundleIdentifier: String
    let osVersion: String
    let hpCloudKitEnabled: Bool
    let hpCloudKitEnabledRawValue: String?
    let hpCloudKitEnabledRawType: String?
    let containerIdentifier: String
    let cloudKitContainerInitialized: Bool
    let cloudKitAvailabilityReason: String
    let lastCKAccountStatusRaw: Int?
    let authenticationState: String
    let mappedErrorCategory: String?
    let errorDomain: String?
    let errorCode: Int?
    let errorDescription: String?
    let reflectedError: String?
    let underlyingErrorChain: [String]
    let recentEntries: [AuthDiagnosticEntry]
}

struct CloudKitFlagParseResult {
    let enabled: Bool
    let rawValue: String?
    let rawType: String?
    let reason: CloudKitAvailabilityReason
}

#if !CI
/// Service responsible for handling Sign in with Apple authentication
/// and CloudKit user identity management
@MainActor
final class AuthenticationService: NSObject, ObservableObject {
    #if CI
    private static let containerIdentifier = "iCloud.com.example.familytodo"
    #else
    private static let containerIdentifier = "iCloud.com.kochanowski.housepulse"
    #endif

    // MARK: - Published Properties

    @Published private(set) var authenticationState: AuthenticationState = .unauthenticated
    @Published private(set) var currentUser: AuthenticatedUser?
    @Published private(set) var latestDiagnostics: AuthDiagnosticsSnapshot?

    // MARK: - Private Properties

    private static let cloudKitEnabledInfoKey = "HPCloudKitEnabled"
    private var cloudKitContainer: CKContainer?
    private var cloudKitEnabledByFlag = false
    private var hpCloudKitEnabledRawValue: String?
    private var hpCloudKitEnabledRawType: String?
    private var cloudKitAvailabilityReason: CloudKitAvailabilityReason = .missingKey
    private var cloudKitContainerInitialized = false
    private var recentDiagnosticEntries: [AuthDiagnosticEntry] = []
    private var lastCKAccountStatusRaw: Int?
    private var lastMappedErrorCategory: AuthMappedErrorCategory?
    private var lastErrorDomain: String?
    private var lastErrorCode: Int?
    private var lastErrorDescription: String?
    private var lastReflectedError: String?
    private var lastUnderlyingErrorChain: [String] = []

    private static let maxDiagnosticEntries = 20

    // MARK: - Initialization

    init(cloudKitContainer: CKContainer? = nil) {
        super.init()
        if let cloudKitContainer {
            self.cloudKitContainer = cloudKitContainer
            cloudKitEnabledByFlag = true
            cloudKitAvailabilityReason = .enabled
            cloudKitContainerInitialized = true
        } else {
            self.cloudKitContainer = makeCloudKitContainer()
        }
        recordDiagnostic(stage: .cloudKitContainerInit)
        refreshLatestDiagnostics()
    }

    // MARK: - Authentication State

    enum AuthenticationState {
        case unauthenticated
        case authenticating
        case authenticated(userID: String)
        case error(AuthenticationError)
    }

    enum AuthenticationError: LocalizedError {
        case cancelled
        case failed(Error)
        case cloudKitNotAvailable
        case userNotFound

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "Authentication was cancelled"
            case let .failed(error):
                "Authentication failed: \(error.localizedDescription)"
            case .cloudKitNotAvailable:
                "CloudKit is not available. Please check your iCloud settings."
            case .userNotFound:
                "User not found in CloudKit"
            }
        }
    }

    // MARK: - Authenticated User Model

    struct AuthenticatedUser: Identifiable {
        let id: String // CloudKit record name
        let appleUserID: String
        let email: String?
        let displayName: String?
        let givenName: String?
        let familyName: String?
    }

    // MARK: - Public Methods

    /// Initiates Sign in with Apple flow.
    func signInWithApple() {
        authenticationState = .authenticating
        recordDiagnostic(stage: .signInTapped)

        guard cloudKitContainer != nil else {
            let error = AuthenticationError.cloudKitNotAvailable
            updateErrorContext(from: error, category: .cloudKitNotAvailable)
            authenticationState = .error(error)
            recordDiagnostic(stage: .signInFailed, error: error)
            return
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Signs out the current user.
    func signOut() {
        currentUser = nil
        authenticationState = .unauthenticated
        clearErrorContext()
        refreshLatestDiagnostics()
    }

    /// Checks CloudKit account status and attempts silent user restore.
    func checkCloudKitStatus() async {
        recordDiagnostic(stage: .startupStatusCheck)

        guard let cloudKitContainer else {
            clearAuthenticatedState()
            return
        }

        do {
            let status = try await cloudKitContainer.accountStatus()
            lastCKAccountStatusRaw = status.rawValue
            refreshLatestDiagnostics()

            switch status {
            case .available:
                do {
                    try await fetchCloudKitUserIdentity()
                } catch {
                    clearAuthenticatedState()
                    let category = Self.mappedErrorCategory(for: error)
                    updateErrorContext(from: error, category: category)
                    recordDiagnostic(stage: .signInFailed, error: error)
                }
            case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                clearAuthenticatedState()
            @unknown default:
                clearAuthenticatedState()
            }
        } catch {
            clearAuthenticatedState()
            let category = Self.mappedErrorCategory(for: error)
            updateErrorContext(from: error, category: category)
            recordDiagnostic(stage: .signInFailed, error: error)
        }
    }

    func diagnosticsReportJSON() -> String {
        if latestDiagnostics == nil {
            refreshLatestDiagnostics()
        }

        guard let latestDiagnostics else {
            return "{\"error\":\"No diagnostics available\"}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(latestDiagnostics),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{\"error\":\"Diagnostics encoding failed\"}"
        }

        return json
    }

    func clearDiagnosticsHistory() {
        recentDiagnosticEntries.removeAll()
        clearErrorContext()
        lastCKAccountStatusRaw = nil
        latestDiagnostics = nil
    }

    // MARK: - Private Methods

    private func fetchCloudKitUserIdentity() async throws {
        guard let cloudKitContainer else {
            throw AuthenticationError.cloudKitNotAvailable
        }

        do {
            recordDiagnostic(stage: .cloudKitUserFetch)

            let userRecordID = try await cloudKitContainer.userRecordID()
            let userID = userRecordID.recordName

            // Keep no PII in diagnostics: only state transitions, no record name.
            authenticationState = .authenticated(userID: userID)
            currentUser = AuthenticatedUser(
                id: userID,
                appleUserID: userID,
                email: nil,
                displayName: nil,
                givenName: nil,
                familyName: nil
            )
            clearErrorContext()
            refreshLatestDiagnostics()
        } catch {
            recordDiagnostic(stage: .cloudKitUserFetch, error: error)
            throw error
        }
    }

    private func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        recordDiagnostic(stage: .authorizationReceived)

        do {
            try await fetchCloudKitUserIdentity()

            if let currentUser {
                let updatedUser = AuthenticatedUser(
                    id: currentUser.id,
                    appleUserID: credential.user,
                    email: credential.email,
                    displayName: [credential.fullName?.givenName, credential.fullName?.familyName]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
                self.currentUser = updatedUser
            }

            clearErrorContext()
            refreshLatestDiagnostics()
        } catch {
            let mappedError = mapSignInError(error)
            let category = Self.mappedErrorCategory(for: error)
            updateErrorContext(from: error, category: category)
            authenticationState = .error(mappedError)
            recordDiagnostic(stage: .signInFailed, error: error)
        }
    }

    private func mapSignInError(_ error: Error) -> AuthenticationError {
        if let authError = error as? AuthenticationError {
            return authError
        }

        switch Self.mappedErrorCategory(for: error) {
        case .notAuthenticated,
             .missingEntitlement,
             .badContainer,
             .permissionFailure,
             .cloudKitNotAvailable:
            return .cloudKitNotAvailable
        case .authorizationCancelled:
            return .cancelled
        case .authorizationFailed, .genericFailure:
            return .failed(error)
        }
    }

    private func makeCloudKitContainer() -> CKContainer? {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: Self.cloudKitEnabledInfoKey)
        let parseResult = Self.parseCloudKitEnabledFlag(rawValue)

        cloudKitEnabledByFlag = parseResult.enabled
        hpCloudKitEnabledRawValue = parseResult.rawValue
        hpCloudKitEnabledRawType = parseResult.rawType
        cloudKitAvailabilityReason = parseResult.reason

        guard parseResult.enabled else {
            cloudKitContainerInitialized = false
            return nil
        }
        cloudKitContainerInitialized = true
        return CKContainer(identifier: Self.containerIdentifier)
    }

    private func clearAuthenticatedState() {
        currentUser = nil
        authenticationState = .unauthenticated
        refreshLatestDiagnostics()
    }

    private func clearErrorContext() {
        lastMappedErrorCategory = nil
        lastErrorDomain = nil
        lastErrorCode = nil
        lastErrorDescription = nil
        lastReflectedError = nil
        lastUnderlyingErrorChain = []
    }

    private func updateErrorContext(from error: Error, category: AuthMappedErrorCategory) {
        let nsError = error as NSError

        lastMappedErrorCategory = category
        lastErrorDomain = nsError.domain
        lastErrorCode = nsError.code
        lastErrorDescription = nsError.localizedDescription
        lastReflectedError = String(reflecting: error)
        lastUnderlyingErrorChain = Self.underlyingErrorChain(from: nsError)
        refreshLatestDiagnostics()
    }

    private func recordDiagnostic(stage: AuthDiagnosticStage, error: Error? = nil) {
        let entry = AuthDiagnosticEntry(
            timestampISO8601: Self.isoTimestamp(),
            stage: stage,
            state: authenticationState.diagnosticState,
            errorSummary: error.map { Self.errorSummary($0) }
        )

        recentDiagnosticEntries.append(entry)
        if recentDiagnosticEntries.count > Self.maxDiagnosticEntries {
            recentDiagnosticEntries.removeFirst(recentDiagnosticEntries.count - Self.maxDiagnosticEntries)
        }

        refreshLatestDiagnostics()
    }

    private func refreshLatestDiagnostics() {
        latestDiagnostics = AuthDiagnosticsSnapshot(
            timestampISO8601: Self.isoTimestamp(),
            appVersion: Self.infoValue(for: "CFBundleShortVersionString"),
            appBuild: Self.infoValue(for: "CFBundleVersion"),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hpCloudKitEnabled: cloudKitEnabledByFlag,
            hpCloudKitEnabledRawValue: hpCloudKitEnabledRawValue,
            hpCloudKitEnabledRawType: hpCloudKitEnabledRawType,
            containerIdentifier: Self.containerIdentifier,
            cloudKitContainerInitialized: cloudKitContainerInitialized,
            cloudKitAvailabilityReason: cloudKitAvailabilityReason.rawValue,
            lastCKAccountStatusRaw: lastCKAccountStatusRaw,
            authenticationState: authenticationState.diagnosticState,
            mappedErrorCategory: lastMappedErrorCategory?.rawValue,
            errorDomain: lastErrorDomain,
            errorCode: lastErrorCode,
            errorDescription: lastErrorDescription,
            reflectedError: lastReflectedError,
            underlyingErrorChain: lastUnderlyingErrorChain,
            recentEntries: recentDiagnosticEntries
        )
    }

    private static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) | code=\(nsError.code) | description=\(nsError.localizedDescription)"
    }

    private static func infoValue(for key: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return value
        }
        return "unknown"
    }

    private static func isoTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            await handleAppleIDCredential(credential)
        }
    }

    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        _Concurrency.Task { [weak self] in
            guard let self else { return }

            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                await handleAuthorizationCancelled()
            } else {
                await handleAuthorizationFailure(error)
            }
        }
    }

    private func handleAuthorizationCancelled() async {
        authenticationState = .unauthenticated
        clearErrorContext()
        recordDiagnostic(stage: .authorizationCancelled)
    }

    private func handleAuthorizationFailure(_ error: Error) async {
        let mappedError = mapSignInError(error)
        let category = Self.mappedErrorCategory(for: error)
        updateErrorContext(from: error, category: category)
        authenticationState = .error(mappedError)
        recordDiagnostic(stage: .signInFailed, error: error)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    @MainActor
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else {
            fatalError("No window found for presenting Sign in with Apple")
        }
        return window
    }
}
#else
@MainActor
final class AuthenticationService: NSObject, ObservableObject {
    @Published private(set) var authenticationState: AuthenticationState = .unauthenticated
    @Published private(set) var currentUser: AuthenticatedUser?
    @Published private(set) var latestDiagnostics: AuthDiagnosticsSnapshot?

    private static let containerIdentifier = "iCloud.com.example.familytodo"
    private static let cloudKitEnabledInfoKey = "HPCloudKitEnabled"
    private var cloudKitEnabledByFlag = false
    private var hpCloudKitEnabledRawValue: String?
    private var hpCloudKitEnabledRawType: String?
    private var cloudKitAvailabilityReason: CloudKitAvailabilityReason = .disabledByFlag
    private var cloudKitContainerInitialized = false
    private var recentDiagnosticEntries: [AuthDiagnosticEntry] = []
    private static let maxDiagnosticEntries = 20

    enum AuthenticationState {
        case unauthenticated
        case authenticating
        case authenticated(userID: String)
        case error(AuthenticationError)
    }

    enum AuthenticationError: LocalizedError {
        case cancelled
        case failed(Error)
        case cloudKitNotAvailable
        case userNotFound

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "Authentication was cancelled"
            case let .failed(error):
                "Authentication failed: \(error.localizedDescription)"
            case .cloudKitNotAvailable:
                "CloudKit is not available. Please check your iCloud settings."
            case .userNotFound:
                "User not found in CloudKit"
            }
        }
    }

    struct AuthenticatedUser: Identifiable {
        let id: String
        let appleUserID: String
        let email: String?
        let displayName: String?
        let givenName: String?
        let familyName: String?
    }

    override init() {
        super.init()
        let rawValue = Bundle.main.object(forInfoDictionaryKey: Self.cloudKitEnabledInfoKey)
        let parseResult = Self.parseCloudKitEnabledFlag(rawValue)
        cloudKitEnabledByFlag = parseResult.enabled
        hpCloudKitEnabledRawValue = parseResult.rawValue
        hpCloudKitEnabledRawType = parseResult.rawType
        cloudKitAvailabilityReason = parseResult.reason
        cloudKitContainerInitialized = false
        recordDiagnostic(stage: .cloudKitContainerInit)
        refreshLatestDiagnostics(mappedErrorCategory: nil, error: nil)
    }

    func signInWithApple() {
        authenticationState = .error(.cloudKitNotAvailable)
        recordDiagnostic(stage: .signInFailed, error: AuthenticationError.cloudKitNotAvailable)
        refreshLatestDiagnostics(mappedErrorCategory: .cloudKitNotAvailable, error: AuthenticationError.cloudKitNotAvailable)
    }

    func signOut() {
        currentUser = nil
        authenticationState = .unauthenticated
        refreshLatestDiagnostics(mappedErrorCategory: nil, error: nil)
    }

    func checkCloudKitStatus() async {
        authenticationState = .unauthenticated
        recordDiagnostic(stage: .startupStatusCheck)
        refreshLatestDiagnostics(mappedErrorCategory: nil, error: nil)
    }

    func diagnosticsReportJSON() -> String {
        if latestDiagnostics == nil {
            refreshLatestDiagnostics(mappedErrorCategory: nil, error: nil)
        }

        guard let latestDiagnostics else {
            return "{\"error\":\"No diagnostics available\"}"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(latestDiagnostics),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{\"error\":\"Diagnostics encoding failed\"}"
        }

        return json
    }

    func clearDiagnosticsHistory() {
        recentDiagnosticEntries.removeAll()
        latestDiagnostics = nil
    }

    private func recordDiagnostic(stage: AuthDiagnosticStage, error: Error? = nil) {
        let entry = AuthDiagnosticEntry(
            timestampISO8601: Self.isoTimestamp(),
            stage: stage,
            state: authenticationState.diagnosticState,
            errorSummary: error.map { Self.errorSummary($0) }
        )

        recentDiagnosticEntries.append(entry)
        if recentDiagnosticEntries.count > Self.maxDiagnosticEntries {
            recentDiagnosticEntries.removeFirst(recentDiagnosticEntries.count - Self.maxDiagnosticEntries)
        }
    }

    private func refreshLatestDiagnostics(mappedErrorCategory: AuthMappedErrorCategory?, error: Error?) {
        let nsError = error.map { $0 as NSError }

        latestDiagnostics = AuthDiagnosticsSnapshot(
            timestampISO8601: Self.isoTimestamp(),
            appVersion: Self.infoValue(for: "CFBundleShortVersionString"),
            appBuild: Self.infoValue(for: "CFBundleVersion"),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hpCloudKitEnabled: cloudKitEnabledByFlag,
            hpCloudKitEnabledRawValue: hpCloudKitEnabledRawValue,
            hpCloudKitEnabledRawType: hpCloudKitEnabledRawType,
            containerIdentifier: Self.containerIdentifier,
            cloudKitContainerInitialized: cloudKitContainerInitialized,
            cloudKitAvailabilityReason: cloudKitAvailabilityReason.rawValue,
            lastCKAccountStatusRaw: nil,
            authenticationState: authenticationState.diagnosticState,
            mappedErrorCategory: mappedErrorCategory?.rawValue,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDescription: nsError?.localizedDescription,
            reflectedError: error.map(String.init(reflecting:)),
            underlyingErrorChain: nsError.map(Self.underlyingErrorChain(from:)) ?? [],
            recentEntries: recentDiagnosticEntries
        )
    }

    private static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) | code=\(nsError.code) | description=\(nsError.localizedDescription)"
    }

    private static func infoValue(for key: String) -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return value
        }
        return "unknown"
    }

    private static func isoTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
#endif

extension AuthenticationService {
    static func parseCloudKitEnabledFlag(_ rawValue: Any?) -> CloudKitFlagParseResult {
        guard let rawValue else {
            return CloudKitFlagParseResult(
                enabled: false,
                rawValue: nil,
                rawType: nil,
                reason: .missingKey
            )
        }

        switch rawValue {
        case let boolValue as Bool:
            return CloudKitFlagParseResult(
                enabled: boolValue,
                rawValue: String(boolValue),
                rawType: "Bool",
                reason: boolValue ? .enabled : .disabledByFlag
            )

        case let numberValue as NSNumber:
            let enabled = numberValue.boolValue
            return CloudKitFlagParseResult(
                enabled: enabled,
                rawValue: numberValue.stringValue,
                rawType: "NSNumber",
                reason: enabled ? .enabled : .disabledByFlag
            )

        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()

            if ["yes", "true", "1"].contains(normalized) {
                return CloudKitFlagParseResult(
                    enabled: true,
                    rawValue: trimmed,
                    rawType: "String",
                    reason: .enabled
                )
            }

            if ["no", "false", "0"].contains(normalized) {
                return CloudKitFlagParseResult(
                    enabled: false,
                    rawValue: trimmed,
                    rawType: "String",
                    reason: .disabledByFlag
                )
            }

            return CloudKitFlagParseResult(
                enabled: false,
                rawValue: trimmed,
                rawType: "String",
                reason: .parseFailure
            )

        default:
            return CloudKitFlagParseResult(
                enabled: false,
                rawValue: String(describing: rawValue),
                rawType: String(reflecting: type(of: rawValue)),
                reason: .parseFailure
            )
        }
    }

    static func mappedErrorCategory(for error: Error) -> AuthMappedErrorCategory {
        if let authError = error as? AuthenticationError {
            switch authError {
            case .cancelled:
                return .authorizationCancelled
            case .cloudKitNotAvailable:
                return .cloudKitNotAvailable
            case .failed, .userNotFound:
                return .genericFailure
            }
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .notAuthenticated:
                return .notAuthenticated
            case .missingEntitlement:
                return .missingEntitlement
            case .badContainer:
                return .badContainer
            case .permissionFailure:
                return .permissionFailure
            default:
                return .genericFailure
            }
        }

        #if !CI
        if let authorizationError = error as? ASAuthorizationError {
            if authorizationError.code == .canceled {
                return .authorizationCancelled
            }
            return .authorizationFailed
        }
        #endif

        return .genericFailure
    }

    static func underlyingErrorChain(from nsError: NSError) -> [String] {
        var chain: [String] = []
        var currentError: NSError? = nsError
        var visited = Set<ObjectIdentifier>()

        while let error = currentError {
            let objectID = ObjectIdentifier(error)
            if !visited.insert(objectID).inserted {
                break
            }

            let summary = "domain=\(error.domain) | code=\(error.code) | description=\(error.localizedDescription)"
            chain.append(summary)

            if let underlyingNSError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                currentError = underlyingNSError
            } else if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
                currentError = underlyingError as NSError
            } else {
                currentError = nil
            }
        }

        return chain
    }
}

private extension AuthenticationService.AuthenticationState {
    var diagnosticState: String {
        switch self {
        case .unauthenticated:
            return "unauthenticated"
        case .authenticating:
            return "authenticating"
        case .authenticated:
            return "authenticated"
        case .error:
            return "error"
        }
    }
}
