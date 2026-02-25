import CoreText
import Foundation
import UIKit

struct FontRegistrationItem {
    let fileName: String
    let postScriptName: String
    let familyAliases: [String]
    let foundInRootBundle: Bool
    let foundInResourcesFonts: Bool
    let registrationAttempted: Bool
    let registrationSuccess: Bool
    let postScriptDetected: Bool
    let registrationError: String?
    let availableFamilyMatches: [String]
    let availableFontNames: [String]
}

struct FontRegistrationReport {
    let generatedAt: Date
    let items: [FontRegistrationItem]

    static let empty = FontRegistrationReport(generatedAt: .distantPast, items: [])

    var statusSummary: String {
        items
            .map { "\($0.postScriptName)=\($0.postScriptDetected ? "ok" : "missing")" }
            .sorted()
            .joined(separator: ", ")
    }

    func isFontAvailable(postScriptName: String) -> Bool {
        item(for: postScriptName)?.postScriptDetected ?? false
    }

    func item(for postScriptName: String) -> FontRegistrationItem? {
        items.first { $0.postScriptName == postScriptName }
    }
}

enum FontRegistrar {
    struct Asset {
        let fileName: String
        let postScriptName: String
        let familyAliases: [String]
    }

    static let bundledAssets: [Asset] = [
        Asset(
            fileName: "PressStart2P-Regular.ttf",
            postScriptName: "PressStart2P-Regular",
            familyAliases: ["Press Start 2P"]
        ),
        Asset(
            fileName: "SpecialElite-Regular.ttf",
            postScriptName: "SpecialElite-Regular",
            familyAliases: ["Special Elite"]
        ),
        Asset(
            fileName: "CaveatBrush-Regular.ttf",
            postScriptName: "CaveatBrush-Regular",
            familyAliases: ["Caveat Brush"]
        ),
        Asset(
            fileName: "VT323-Regular.ttf",
            postScriptName: "VT323-Regular",
            familyAliases: ["VT323"]
        ),
    ]

    static func registerBundledFonts() -> FontRegistrationReport {
        let reportItems = bundledAssets.map { spec in
            register(asset: spec)
        }
        return FontRegistrationReport(generatedAt: Date(), items: reportItems)
    }

    private static func register(asset: Asset) -> FontRegistrationItem {
        let rootURL = bundleURL(fileName: asset.fileName, subdirectory: nil)
        let resourcesURL = bundleURL(fileName: asset.fileName, subdirectory: "Resources/Fonts")
        let registrationURL = rootURL ?? resourcesURL
        let wasAvailable = UIFont(name: asset.postScriptName, size: 12) != nil

        var registrationError: String?
        var registrationSuccess = wasAvailable
        let registrationAttempted = !wasAvailable && registrationURL != nil

        if !wasAvailable, let registrationURL {
            var cfError: Unmanaged<CFError>?
            let didRegister = CTFontManagerRegisterFontsForURL(
                registrationURL as CFURL,
                .process,
                &cfError
            )

            if let cfError {
                registrationError = (cfError.takeRetainedValue() as Error).localizedDescription
            }
            registrationSuccess = didRegister
        }

        let isNowAvailable = UIFont(name: asset.postScriptName, size: 12) != nil
        let familyMatches = matchedFamilyNames(for: [asset.postScriptName] + asset.familyAliases)
        let familyFontNames = familyMatches
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .uniquePreservingOrder()

        return FontRegistrationItem(
            fileName: asset.fileName,
            postScriptName: asset.postScriptName,
            familyAliases: asset.familyAliases,
            foundInRootBundle: rootURL != nil,
            foundInResourcesFonts: resourcesURL != nil,
            registrationAttempted: registrationAttempted,
            registrationSuccess: registrationSuccess || isNowAvailable,
            postScriptDetected: isNowAvailable,
            registrationError: registrationError,
            availableFamilyMatches: familyMatches,
            availableFontNames: familyFontNames
        )
    }

    private static func bundleURL(fileName: String, subdirectory: String?) -> URL? {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let baseName = URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
        return Bundle.main.url(
            forResource: baseName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: subdirectory
        )
    }

    private static func matchedFamilyNames(for aliases: [String]) -> [String] {
        let normalizedAliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return UIFont.familyNames
            .filter { familyName in
                let normalizedFamily = familyName.lowercased()
                return normalizedAliases.contains { alias in
                    normalizedFamily.contains(alias) || alias.contains(normalizedFamily)
                }
            }
            .sorted()
    }
}

private extension Array where Element: Hashable {
    func uniquePreservingOrder() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for element in self where seen.insert(element).inserted {
            result.append(element)
        }
        return result
    }
}
