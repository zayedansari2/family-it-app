@preconcurrency import AppKit
import Foundation

enum AppLaunchResult: Equatable, Sendable {
    case opened(displayName: String)
    case notFound(requestedName: String)
    case failed(displayName: String, reason: String)
}

/// Boundary for local Mac actions. Future automation features can use separate
/// implementations without coupling AppKit operations to the SwiftUI views.
@MainActor protocol AppLaunching: AnyObject {
    func openApplication(named requestedName: String) async -> AppLaunchResult
}

@MainActor final class MacAppLauncher: AppLaunching {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    private let knownBundleIdentifiers: [String: String] = [
        "app store": "com.apple.AppStore",
        "calendar": "com.apple.iCal",
        "chrome": "com.google.Chrome",
        "facetime": "com.apple.FaceTime",
        "finder": "com.apple.finder",
        "google chrome": "com.google.Chrome",
        "mail": "com.apple.mail",
        "maps": "com.apple.Maps",
        "messages": "com.apple.MobileSMS",
        "microsoft excel": "com.microsoft.Excel",
        "microsoft powerpoint": "com.microsoft.Powerpoint",
        "microsoft word": "com.microsoft.Word",
        "music": "com.apple.Music",
        "notes": "com.apple.Notes",
        "photos": "com.apple.Photos",
        "safari": "com.apple.Safari",
        "settings": "com.apple.systempreferences",
        "system settings": "com.apple.systempreferences",
        "zoom": "us.zoom.xos",
        "zoom meeting": "us.zoom.xos"
    ]

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func openApplication(named requestedName: String) async -> AppLaunchResult {
        let cleanedName = Self.cleanApplicationName(requestedName)
        guard let applicationURL = findApplication(named: cleanedName) else {
            return .notFound(requestedName: cleanedName)
        }

        let displayName = applicationURL.deletingPathExtension().lastPathComponent
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true

        return await withCheckedContinuation { continuation in
            workspace.openApplication(at: applicationURL, configuration: configuration) { @Sendable application, error in
                if application != nil {
                    continuation.resume(returning: .opened(displayName: displayName))
                } else {
                    let reason = error?.localizedDescription ?? "The Mac did not provide a reason."
                    continuation.resume(returning: .failed(displayName: displayName, reason: reason))
                }
            }
        }
    }

    private func findApplication(named name: String) -> URL? {
        let lookupName = name.lowercased()
        if let bundleIdentifier = knownBundleIdentifiers[lookupName],
           let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }

        let searchDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for directory in searchDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            if let match = contents.first(where: { url in
                url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                    && url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return match
            }
        }

        return nil
    }

    private static func cleanApplicationName(_ name: String) -> String {
        var cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let removableSuffixes = [" for me", " please", " application", " app"]
        for suffix in removableSuffixes where cleaned.lowercased().hasSuffix(suffix) {
            cleaned.removeLast(suffix.count)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        if cleaned.lowercased().hasPrefix("the ") {
            cleaned.removeFirst(4)
        }
        return cleaned
    }
}

enum OpenAppRequestParser {
    static func applicationName(from request: String) -> String? {
        let command = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercaseCommand = command.lowercased()
        let prefixes = [
            "can you please open ",
            "could you please open ",
            "can you open ",
            "could you open ",
            "i would like to open ",
            "i want to open ",
            "please open ",
            "open up ",
            "launch ",
            "start ",
            "open "
        ]

        guard let prefix = prefixes.first(where: lowercaseCommand.hasPrefix) else {
            return nil
        }

        let name = String(command.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return name.isEmpty ? nil : name
    }
}

