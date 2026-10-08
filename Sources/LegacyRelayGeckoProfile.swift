import Foundation
import Darwin

enum LegacyRelayGeckoProfile {
    private static let activeProviderKey = "LegacyRelay.Gecko.ActiveProvider"
    private static let clearPrefix = "LegacyRelay.Gecko.Clear."
    private static let pendingImportPrefix = "LegacyRelay.Gecko.PendingImport."

    static func safeIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        let safe = value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
        return safe.isEmpty ? "gecko-default" : safe
    }

    static func activeProviderIdentifier(
        default defaultIdentifier: String
    ) -> String {
        return safeIdentifier(defaultIdentifier)
    }

    static func selectForNextLaunch(providerIdentifier: String) {
        UserDefaults.standard.set(
            safeIdentifier(providerIdentifier),
            forKey: activeProviderKey
        )
        UserDefaults.standard.synchronize()
    }

    static func isActive(
        providerIdentifier: String,
        default defaultIdentifier: String
    ) -> Bool {
        return activeProviderIdentifier(default: defaultIdentifier)
            == safeIdentifier(providerIdentifier)
    }

    static func requestClear(providerIdentifier: String) {
        let identifier = safeIdentifier(providerIdentifier)
        UserDefaults.standard.set(
            identifier,
            forKey: activeProviderKey
        )
        UserDefaults.standard.set(
            true,
            forKey: clearPrefix + identifier
        )
    }

    static func profileURL(providerIdentifier: String) -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return support
            .appendingPathComponent("LegacyRelay", isDirectory: true)
            .appendingPathComponent("GeckoProfiles", isDirectory: true)
            .appendingPathComponent(
                safeIdentifier(providerIdentifier),
                isDirectory: true
            )
            .appendingPathComponent(".mozilla", isDirectory: true)
            .appendingPathComponent("firefox", isDirectory: true)
    }

    private static func legacyCacheProfileURL(
        providerIdentifier: String
    ) -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let base = caches.appendingPathComponent("LegacyRelay", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard folder.lastPathComponent.hasPrefix("Gecko") else { continue }
            let candidate = folder
                .appendingPathComponent(safeIdentifier(providerIdentifier), isDirectory: true)
                .appendingPathComponent(".mozilla", isDirectory: true)
                .appendingPathComponent("firefox", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func pendingImportKey(providerIdentifier: String) -> String {
        return pendingImportPrefix + safeIdentifier(providerIdentifier)
    }

    private static func restorePendingSnapchatSessionBeforeGeckoStarts(
        identifier: String, profile: URL
    ) {
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        let pendingKey = pendingImportKey(providerIdentifier: identifier)
        let transactionKey = "LegacyRelay.Gecko.ImportTransaction.snapchat"
        let noticeKey = "LegacyRelay.Gecko.ImportNotice"
        let parent = profile.deletingLastPathComponent()
        let backupPrefix = ".legacyrelay-snap-before-import-"
        let failedPrefix = ".legacyrelay-snap-incomplete-"

        if let backupPath = defaults.string(forKey: transactionKey) {
            let backup = URL(fileURLWithPath: backupPath)
            let safe = backup.deletingLastPathComponent().standardizedFileURL ==
                parent.standardizedFileURL && backup.lastPathComponent.hasPrefix(backupPrefix)
            guard safe else {
                defaults.set("Import recovery needs attention. Your app data was not deleted.",
                             forKey: noticeKey)
                defaults.synchronize()
                NSLog("LegacyRelay Snapchat import: unexpected recovery marker")
                return
            }
            if fm.fileExists(atPath: backup.path) {
                do {
                    if fm.fileExists(atPath: profile.path) {
                        let interrupted = parent.appendingPathComponent(
                            failedPrefix + UUID().uuidString, isDirectory: true)
                        try fm.moveItem(at: profile, to: interrupted)
                    }
                    try fm.moveItem(at: backup, to: profile)
                } catch {
                    defaults.set("Import recovery failed. Keep this installation and its data.",
                                 forKey: noticeKey)
                    defaults.synchronize()
                    NSLog("LegacyRelay Snapchat import: transaction recovery failed")
                    return
                }
            } else if !fm.fileExists(atPath: profile.path) {
                defaults.set("Import recovery failed. Keep this installation and its data.",
                             forKey: noticeKey)
                defaults.synchronize()
                NSLog("LegacyRelay Snapchat import: missing recovery directory")
                return
            }
            defaults.removeObject(forKey: transactionKey)
            defaults.synchronize()
        }

        guard let pendingPath = defaults.string(forKey: pendingKey) else { return }
        let pendingArchive = URL(fileURLWithPath: pendingPath)
        var archive = pendingArchive
        var backup: URL?
        var oldProfileWasMoved = false
        var restoreFailureStage = "checking the imported file"
        do {
            guard let support = fm.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 1)
            }
            let expected = support.appendingPathComponent(
                "LegacyRelay/PendingGeckoSessions", isDirectory: true)
            let stagedName = pendingArchive.lastPathComponent
            guard !stagedName.isEmpty, stagedName != ".", stagedName != "..",
                  stagedName == (stagedName as NSString).lastPathComponent else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 21)
            }
            let trustedStaged = expected.appendingPathComponent(
                stagedName, isDirectory: false)
            if pendingArchive.deletingLastPathComponent().standardizedFileURL !=
                    expected.standardizedFileURL {
                guard fm.fileExists(atPath: trustedStaged.path) else {
                    throw NSError(domain: "LegacyRelay.SnapRestore", code: 21)
                }
                archive = trustedStaged
            }
            let archiveValues = try archive.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard archiveValues.isSymbolicLink != true else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 23)
            }
            guard archiveValues.isRegularFile == true else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 22)
            }
            restoreFailureStage = "reading the backup header"
            let handle = try FileHandle(forReadingFrom: archive)
            let signature = handle.readData(ofLength: 29)
            handle.closeFile()
            guard signature == Data("LEGACYRELAY_GECKO_SESSION_V1\n".utf8) else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 3)
            }
            try fm.createDirectory(at: parent, withIntermediateDirectories: true,
                                   attributes: nil)
            let staged = parent.appendingPathComponent(
                ".legacyrelay-snap-restored-" + UUID().uuidString,
                isDirectory: true)
            try fm.createDirectory(at: staged, withIntermediateDirectories: true,
                                   attributes: nil)
            restoreFailureStage = "restoring and verifying the backup"
            try LegacyRelayGeckoSessionArchive.restore(
                archiveURL: archive,
                providerIdentifier: identifier,
                destinationProfileURL: staged)
            restoreFailureStage = "checking the restored files"
            let entries = try fm.contentsOfDirectory(atPath: staged.path)
            guard !entries.isEmpty else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 4)
            }
            restoreFailureStage = "preserving the previous profile"
            if fm.fileExists(atPath: profile.path) {
                let original = parent.appendingPathComponent(
                    backupPrefix + UUID().uuidString, isDirectory: true)
                backup = original
                defaults.set(original.path, forKey: transactionKey)
                defaults.synchronize()
                try fm.moveItem(at: profile, to: original)
                oldProfileWasMoved = true
            }
            restoreFailureStage = "activating the restored profile"
            try fm.moveItem(at: staged, to: profile)
            guard fm.fileExists(atPath: profile.path) else {
                throw NSError(domain: "LegacyRelay.SnapRestore", code: 5)
            }
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: transactionKey)
            defaults.set("Session restored on this device. Snapchat login is not yet verified.",
                         forKey: noticeKey)
            defaults.synchronize()
            NSLog("LegacyRelay Snapchat import: local profile restore complete")
        } catch {
            var recovered = true
            if oldProfileWasMoved, let original = backup,
               fm.fileExists(atPath: original.path) {
                do {
                    if fm.fileExists(atPath: profile.path) {
                        let incomplete = parent.appendingPathComponent(
                            failedPrefix + UUID().uuidString, isDirectory: true)
                        try fm.moveItem(at: profile, to: incomplete)
                    }
                    try fm.moveItem(at: original, to: profile)
                } catch {
                    recovered = false
                }
            }
            defaults.removeObject(forKey: pendingKey)
            let nsError = error as NSError
            if recovered {
                defaults.removeObject(forKey: transactionKey)
                defaults.set(
                    "Session import failed while \(restoreFailureStage). Error \(nsError.domain):\(nsError.code). Previous profile kept.",
                    forKey: noticeKey)
            } else {
                defaults.set("Import failed and recovery needs attention. Keep this app installed.",
                             forKey: noticeKey)
            }
            defaults.synchronize()
            NSLog("LegacyRelay Snapchat import failed: domain=%@ code=%ld step=%@",
                  nsError.domain, nsError.code, restoreFailureStage)
        }
    }

    static func prepareBeforeGeckoStarts(
        defaultProfileIdentifier: String
    ) {
        let identifier = activeProviderIdentifier(
            default: defaultProfileIdentifier
        )

        guard let profile = profileURL(
            providerIdentifier: identifier
        ) else {
            return
        }

        let r5LiveKey =
            "LegacyRelay.Gecko.LiveImportBackup." + identifier

        if let backupPath = UserDefaults.standard.string(
            forKey: r5LiveKey
        ) {
            let backupURL = URL(fileURLWithPath: backupPath)
            let parent = profile.deletingLastPathComponent()

            if backupURL.deletingLastPathComponent().path == parent.path,
               backupURL.lastPathComponent.hasPrefix(".preimport-"),
               FileManager.default.fileExists(atPath: backupURL.path) {

                let failed = parent.appendingPathComponent(
                    ".r5-live-import-failed-" + UUID().uuidString,
                    isDirectory: true
                )

                do {
                    if FileManager.default.fileExists(atPath: profile.path) {
                        try FileManager.default.moveItem(
                            at: profile,
                            to: failed
                        )
                    }

                    try FileManager.default.moveItem(
                        at: backupURL,
                        to: profile
                    )

                    try? FileManager.default.removeItem(at: failed)

                    NSLog(
                        "LegacyRelay recovered Gecko profile after interrupted import."
                    )
                } catch {
                    NSLog(
                        "LegacyRelay profile recovery failed safely: %@",
                        error.localizedDescription
                    )
                }
            }

            UserDefaults.standard.removeObject(forKey: r5LiveKey)
            UserDefaults.standard.synchronize()
        }


        
        
        
        if !FileManager.default.fileExists(
            atPath: profile.path
        ),
        let oldProfile = legacyCacheProfileURL(
            providerIdentifier: identifier
        ),
        FileManager.default.fileExists(
            atPath: oldProfile.path
        ) {
            do {
                try FileManager.default.createDirectory(
                    at: profile.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                try FileManager.default.moveItem(
                    at: oldProfile,
                    to: profile
                )

                NSLog(
                    "LegacyRelay migrated Gecko profile to Application Support."
                )
            } catch {
                NSLog(
                    "LegacyRelay Gecko profile migration failed: %@",
                    error.localizedDescription
                )
            }
        }

        let clearKey = clearPrefix + identifier
        if UserDefaults.standard.bool(forKey: clearKey) {
            UserDefaults.standard.set(false, forKey: clearKey)
            UserDefaults.standard.synchronize()
            NSLog(
                "LegacyRelay ignored legacy destructive Gecko clear flag."
            )
        }

        let pendingKey = pendingImportKey(providerIdentifier: identifier)
        if identifier.lowercased() == "snapchat" {
            restorePendingSnapchatSessionBeforeGeckoStarts(
                identifier: identifier,
                profile: profile
            )
        } else if UserDefaults.standard.string(forKey: pendingKey) != nil {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            UserDefaults.standard.synchronize()
            UserDefaults.standard.set(
                "Legacy Gecko profile import is unavailable. Your current session was preserved.",
                forKey: "LegacyRelay.Gecko.ImportNotice"
            )
        }

        try? FileManager.default.createDirectory(
            at: profile,
            withIntermediateDirectories: true,
            attributes: nil
        )

        setenv("MOZ_APP_DATA", profile.path, 1)
        setenv("MOZ_LOCAL_APP_DATA", profile.path, 1)
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
