import Foundation
import SQLite3
import Darwin

enum LegacyRelayGeckoSessionArchive {
    private static let magic =
        Data("LEGACYRELAY_GECKO_SESSION_V1\n".utf8)

    private static let excludedPrefixes: [String] = [
        "cache2/",
        "startupCache/",
        "shader-cache/",
        "crashes/",
        "minidumps/",
        "thumbnails/",
        "safebrowsing/"
    ]

    private static let excludedNames: Set<String> = [
        ".parentlock",
        "parent.lock",
        "lock"
    ]

    private static func isSQLiteSidecar(_ relative: String) -> Bool {
        let name = URL(fileURLWithPath: relative).lastPathComponent.lowercased()
        return name.hasSuffix("-wal") || name.hasSuffix("-shm") ||
            name.hasSuffix("-journal")
    }

    private static func isSQLiteFile(_ url: URL) throws -> Bool {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        return input.readData(ofLength: 16) == Data([83,81,76,105,116,101,32,102,111,114,109,97,116,32,51,0])
    }

    private static func checkSQLite(_ url: URL) throws {
        var db: OpaquePointer?
        let rc = url.path.withCString {
            sqlite3_open_v2($0, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard rc == SQLITE_OK, let conn = db else {
            if db != nil { sqlite3_close(db) }
            throw transferError("Session database could not be opened.")
        }
        defer { sqlite3_close(conn) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(conn, "PRAGMA quick_check(1)", -1, &stmt, nil) == SQLITE_OK,
              let query = stmt else {
            if stmt != nil { sqlite3_finalize(stmt) }
            throw transferError("Session database could not be checked.")
        }
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW,
              let ptr = sqlite3_column_text(query, 0),
              String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)) == "ok" else {
            throw transferError("Session database is damaged or incomplete.")
        }
    }

    private static func makeSQLiteSnapshot(_ original: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-sqlite-snapshot-" + UUID().uuidString + ".sqlite")
        var sourceDB: OpaquePointer?
        var targetDB: OpaquePointer?
        var succeeded = false
        defer {
            if sourceDB != nil { sqlite3_close(sourceDB) }
            if targetDB != nil { sqlite3_close(targetDB) }
            if !succeeded { try? FileManager.default.removeItem(at: dest) }
        }
        let s = original.path.withCString {
            sqlite3_open_v2($0, &sourceDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard s == SQLITE_OK, let src = sourceDB else {
            throw transferError("Cannot snapshot the active session database.")
        }
        let t = dest.path.withCString {
            sqlite3_open_v2($0, &targetDB,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard t == SQLITE_OK, let dst = targetDB else {
            throw transferError("Cannot create a consistent database backup.")
        }
        sqlite3_busy_timeout(src, 2500)
        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            throw transferError("Cannot initialize session database backup.")
        }
        var result: Int32 = SQLITE_OK
        var busyCount = 0
        repeat {
            result = sqlite3_backup_step(backup, 128)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                busyCount += 1
                if busyCount >= 40 { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } while result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE && finished == SQLITE_OK else {
            throw transferError("Gecko changed its database during export. Try again later.")
        }
        sqlite3_close(targetDB); targetDB = nil
        sqlite3_close(sourceDB); sourceDB = nil
        try checkSQLite(dest)
        succeeded = true
        return dest
    }

    private static func appendConsistentFile(
        from fileURL: URL, relativePath: String, to out: FileHandle
    ) throws {
        let name = fileURL.lastPathComponent.lowercased()
        let candidate = name.hasSuffix(".sqlite") || name.hasSuffix(".db")
        let sqlite = candidate ? (try isSQLiteFile(fileURL)) : false
        if candidate && name.hasSuffix(".sqlite") && !sqlite {
            throw transferError("Cannot export an invalid SQLite database.")
        }
        let snapshot = sqlite ? try makeSQLiteSnapshot(fileURL) : nil
        defer { if let p = snapshot { try? FileManager.default.removeItem(at: p) } }
        let inputURL = snapshot ?? fileURL
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        let properties = try inputURL.resourceValues(forKeys: [.fileSizeKey])
        guard let rawSize = properties.fileSize, rawSize >= 0 else {
            throw transferError("Cannot determine session file size.")
        }
        let size = UInt64(rawSize)
        let pathData = Data(relativePath.utf8)
        guard pathData.count > 0 && pathData.count <= 4096,
              size <= 8 * 1024 * 1024 * 1024 else {
            throw transferError("Session contains an unsupported file.")
        }
        writeUInt32(UInt32(pathData.count), to: out)
        writeUInt64(size, to: out)
        out.write(pathData)
        var remaining = size
        while remaining > 0 {
            let amount = Int(min(remaining, UInt64(1024 * 1024)))
            let chunk = input.readData(ofLength: amount)
            guard chunk.count == amount else {
                throw transferError("Session file changed while exporting.")
            }
            out.write(chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    private static func validateRestoredCookieDatabase(_ profile: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: profile,
                    includingPropertiesForKeys: [.isRegularFileKey], options: [], errorHandler: nil)
        else { throw transferError("Could not check restored session.") }
        var found = false
        for case let entry as URL in enumerator {
            if entry.lastPathComponent.lowercased() == "cookies.sqlite" {
                found = true
                guard try isSQLiteFile(entry) else {
                    throw transferError("Restored cookie database is invalid.")
                }
                try checkSQLite(entry)
            }
        }
        guard found else { throw transferError("Archive has no Gecko cookie database.") }
    }

    static func exportSession(provider: RelayProvider) throws -> URL {
        let safe = LegacyRelayGeckoProfile.safeIdentifier(
            provider.identifier
        )
        guard safe == "snapchat" else {
            throw NSError(domain: "LegacyRelay.SessionArchive", code: 40,
                userInfo: [NSLocalizedDescriptionKey: "Only Snapchat session exports are supported here."])
        }

        guard let profile = LegacyRelayGeckoProfile.profileURL(
            providerIdentifier: safe
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Gecko profile is unavailable."
                ]
            )
        }

        guard FileManager.default.fileExists(
            atPath: profile.path
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No Gecko session exists for this provider yet."
                ]
            )
        }

        let exportFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyRelayGeckoExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportFolder, withIntermediateDirectories: true, attributes: nil
        )
        let output = exportFolder.appendingPathComponent("snapchat.mgsession")

        if FileManager.default.fileExists(
            atPath: output.path
        ) {
            try FileManager.default.removeItem(
                at: output
            )
        }

        guard FileManager.default.createFile(
            atPath: output.path,
            contents: nil
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 11,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not create the session export file."
                ]
            )
        }

        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        let out = try FileHandle(forWritingTo: output)
        defer {
            try? out.close()
        }

        out.write(magic)

        let providerData = Data(safe.utf8)
        writeUInt32(UInt32(providerData.count), to: out)
        out.write(providerData)

        guard let enumerator = FileManager.default.enumerator(
            at: profile,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not enumerate the Gecko profile."
                ]
            )
        }

        var exportedPaths = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )

            guard values.isRegularFile == true else {
                continue
            }

            let relative = try relativePath(
                fileURL,
                under: profile
            )

            if shouldSkip(relativePath: relative) || isSQLiteSidecar(relative) || relative == "LegacyRelayPortableV2.marker" {
                continue
            }
            guard exportedPaths.insert(relative).inserted else {
                throw transferError("Gecko profile contains duplicate paths. Export cancelled.")
            }

            try appendConsistentFile(
                from: fileURL, relativePath: relative, to: out
            )
        }

        let marker = Data("LegacyRelayPortableV2.marker".utf8)
        writeUInt32(UInt32(marker.count), to: out)
        writeUInt64(0, to: out)
        out.write(marker)
        writeUInt32(0, to: out)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: output.path
        )
        completed = true
        return output
    }

    private static func cookieDatabases(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path),
              let enumerator = manager.enumerator(
                  at: directory,
                  includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey,
                                               .isSymbolicLinkKey, .contentModificationDateKey],
                  options: [],
                  errorHandler: nil
              ) else { return [] }

        let ignoredDirectories: Set<String> = [
            "cache2", "startupCache", "storage", "shader-cache", "crashes",
            "minidumps", "thumbnails", "safebrowsing", "extensions"
        ]
        var results: [URL] = []
        for case let item as URL in enumerator {
            let properties = try? item.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
            ])
            if properties?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if properties?.isDirectory == true {
                if enumerator.level > 5 || ignoredDirectories.contains(item.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if item.lastPathComponent == "cookies.sqlite" && properties?.isRegularFile == true {
                results.append(item)
            }
        }
        return results.sorted {
            let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return first > second
        }
    }

    private static func readCookies(
        from database: URL,
        provider: String,
        host requestedHost: String
    ) throws -> [RelaySessionCookie] {
        var db: OpaquePointer?
        let result = database.path.withCString {
            sqlite3_open_v2($0, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard result == SQLITE_OK, let connection = db else {
            if db != nil { sqlite3_close(db) }
            throw exportError("Could not open Gecko cookie database.")
        }
        defer { sqlite3_close(connection) }

        let sql = "SELECT name, value, host, path, isSecure, isHttpOnly, expiry FROM moz_cookies"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let query = statement else {
            if statement != nil { sqlite3_finalize(statement) }
            throw exportError("Unsupported Gecko cookie database schema.")
        }
        defer { sqlite3_finalize(query) }

        func textAt(_ column: Int32) -> String {
            guard let pointer = sqlite3_column_text(query, column) else { return "" }
            return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
        }

        let now = Date().timeIntervalSince1970
        var cookies: [RelaySessionCookie] = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw exportError("Could not read the live Gecko cookie database.")
            }
            let domain = textAt(2).lowercased()
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let relevant: Bool
            if provider == "snapchat" {
                relevant = host == "snapchat.com" || host.hasSuffix(".snapchat.com") ||
                           host == "snapkit.com" || host.hasSuffix(".snapkit.com")
            } else {
                relevant = !requestedHost.isEmpty &&
                           (host == requestedHost || requestedHost.hasSuffix("." + host))
            }
            if !relevant { continue }

            let expiry = TimeInterval(sqlite3_column_int64(query, 6))
            let sessionOnly = expiry <= 0
            if !sessionOnly && expiry <= now { continue }
            let name = textAt(0)
            if name.isEmpty { continue }
            cookies.append(RelaySessionCookie(
                name: name, value: textAt(1), domain: domain,
                path: textAt(3).isEmpty ? "/" : textAt(3),
                secure: sqlite3_column_int(query, 4) != 0,
                httpOnly: sqlite3_column_int(query, 5) != 0,
                sessionOnly: sessionOnly,
                expires: sessionOnly ? nil : expiry
            ))
        }
        return cookies
    }

    private static func exportError(_ description: String) -> NSError {
        return NSError(domain: "LegacyRelay.SessionExport", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: description])
    }

    // Backward-compatible, explicit backup/restore of the entire Gecko profile.
    // Old legacy binary .mgsession files remain readable by restore().
    static func exportFullProfile(
        providerIdentifier: String
    ) throws -> URL {
        let safe = LegacyRelayGeckoProfile.safeIdentifier(
            providerIdentifier
        )

        guard let profile = LegacyRelayGeckoProfile.profileURL(
            providerIdentifier: safe
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Gecko profile is unavailable."
                ]
            )
        }

        guard FileManager.default.fileExists(
            atPath: profile.path
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No Gecko session exists for this provider yet."
                ]
            )
        }

        let exportName: String
        if safe.lowercased() == "snapchat" {
            exportName = "SnapChat-GeckoProfile.mgsession"
        } else {
            exportName = "custom-GeckoProfile.mgsession"
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportName)

        if FileManager.default.fileExists(
            atPath: output.path
        ) {
            try FileManager.default.removeItem(
                at: output
            )
        }

        FileManager.default.createFile(
            atPath: output.path,
            contents: nil
        )

        let out = try FileHandle(forWritingTo: output)
        defer {
            try? out.close()
        }

        out.write(magic)

        let providerData = Data(safe.utf8)
        writeUInt32(UInt32(providerData.count), to: out)
        out.write(providerData)

        guard let enumerator = FileManager.default.enumerator(
            at: profile,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not enumerate the Gecko profile."
                ]
            )
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )

            guard values.isRegularFile == true else {
                continue
            }

            let relative = try relativePath(
                fileURL,
                under: profile
            )

            if shouldSkip(relativePath: relative) {
                continue
            }

            let pathData = Data(relative.utf8)
            let size = UInt64(values.fileSize ?? 0)

            writeUInt32(UInt32(pathData.count), to: out)
            writeUInt64(size, to: out)
            out.write(pathData)

            let input = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? input.close()
            }

            var remaining = size
            while remaining > 0 {
                let amount = Int(min(remaining, UInt64(1024 * 1024)))
                let chunk = input.readData(ofLength: amount)

                if chunk.isEmpty {
                    throw NSError(
                        domain: "LegacyRelay.SessionArchive",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "A Gecko session file changed while exporting."
                        ]
                    )
                }

                out.write(chunk)
                remaining -= UInt64(chunk.count)
            }
        }

        writeUInt32(0, to: out)
        return output
    }

    static func stageImport(
        archiveURL: URL,
        providerIdentifier: String
    ) throws {
        let safe = LegacyRelayGeckoProfile.safeIdentifier(
            providerIdentifier
        )

        try validate(
            archiveURL: archiveURL,
            providerIdentifier: safe
        )

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Application Support is unavailable."
                ]
            )
        }

        let pendingDirectory = appSupport
            .appendingPathComponent(
                "LegacyRelay/PendingGeckoSessions",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: pendingDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let destination = pendingDirectory
            .appendingPathComponent("\(safe).lrsession")

        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            try FileManager.default.removeItem(
                at: destination
            )
        }

        try FileManager.default.copyItem(
            at: archiveURL,
            to: destination
        )

        UserDefaults.standard.set(
            safe,
            forKey: "LegacyRelay.Gecko.ActiveProvider"
        )

        UserDefaults.standard.set(
            destination.path,
            forKey: LegacyRelayGeckoProfile.pendingImportKey(
                providerIdentifier: safe
            )
        )

        UserDefaults.standard.synchronize()
    }

    static func restore(
        archiveURL: URL,
        providerIdentifier: String,
        destinationProfileURL: URL
    ) throws {
        if LegacyRelayGeckoProfile.safeIdentifier(providerIdentifier) == "snapchat" {
            try validatePortableArchiveV1(
                archiveURL: archiveURL, providerIdentifier: providerIdentifier
            )
        }
        let input = try FileHandle(
            forReadingFrom: archiveURL
        )
        defer {
            try? input.close()
        }

        try validateHeader(
            input: input,
            providerIdentifier: providerIdentifier
        )

        while true {
            let pathLength = try readUInt32(from: input)

            if pathLength == 0 {
                break
            }

            let size = try readUInt64(from: input)

            let pathData = try readExactly(
                Int(pathLength),
                from: input
            )

            guard let relative = String(
                data: pathData,
                encoding: .utf8
            ),
            !relative.isEmpty,
            !relative.hasPrefix("/"),
            !relative.contains("\\"),
            !relative.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
                throw NSError(
                    domain: "LegacyRelay.SessionArchive",
                    code: 6,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The session archive contains an invalid path."
                    ]
                )
            }

            let outputURL = destinationProfileURL
                .appendingPathComponent(relative)

            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw NSError(domain: "LegacyRelay.SnapRestoreIO", code: 31,
                              userInfo: [NSUnderlyingErrorKey: error])
            }

            let descriptor = outputURL.path.withCString {
                Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
            }
            guard descriptor >= 0 else {
                let underlying = NSError(domain: NSPOSIXErrorDomain,
                                         code: Int(Darwin.errno))
                throw NSError(domain: "LegacyRelay.SnapRestoreIO", code: 34,
                              userInfo: [NSUnderlyingErrorKey: underlying])
            }
            let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer {
                try? output.close()
            }

            var remaining = size
            while remaining > 0 {
                let amount = Int(
                    min(remaining, UInt64(1024 * 1024))
                )
                let chunk = try readExactly(
                    amount,
                    from: input
                )
                output.write(chunk)
                remaining -= UInt64(chunk.count)
            }
        }
            if LegacyRelayGeckoProfile.safeIdentifier(providerIdentifier) == "snapchat" {
            do {
                try validateRestoredCookieDatabase(destinationProfileURL)
            } catch {
                throw NSError(domain: "LegacyRelay.SnapRestoreIO", code: 35,
                              userInfo: [NSUnderlyingErrorKey: error])
            }
        }
    }

    private static func validate(
        archiveURL: URL,
        providerIdentifier: String
    ) throws {
        let input = try FileHandle(
            forReadingFrom: archiveURL
        )
        defer {
            try? input.close()
        }

        try validateHeader(
            input: input,
            providerIdentifier: providerIdentifier
        )
    }

    private static func validateHeader(
        input: FileHandle,
        providerIdentifier: String
    ) throws {
        let readMagic = try readExactly(
            magic.count,
            from: input
        )

        guard readMagic == magic else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This is not a LegacyRelay Gecko session file."
                ]
            )
        }

        let providerLength = try readUInt32(
            from: input
        )

        let providerData = try readExactly(
            Int(providerLength),
            from: input
        )

        let archiveProvider = String(
            data: providerData,
            encoding: .utf8
        )

        guard archiveProvider
            == LegacyRelayGeckoProfile.safeIdentifier(
                providerIdentifier
            ) else {
            throw NSError(
                domain: "LegacyRelay.SessionArchive",
                code: 8,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This session belongs to a different provider."
                ]
            )
        }
    }

    private static func shouldSkip(
        relativePath: String
    ) -> Bool {
        let normalized = relativePath
            .replacingOccurrences(
                of: "\\",
                with: "/"
            )

        let name = URL(
            fileURLWithPath: normalized
        ).lastPathComponent

        if excludedNames.contains(name) {
            return true
        }

        return excludedPrefixes.contains {
            normalized.hasPrefix($0)
        }
    }

    private static func relativePath(
        _ fileURL: URL,
        under root: URL
    ) throws -> String {
        let canonicalRoot = root.standardizedFileURL
            .resolvingSymlinksInPath().path
        let canonicalFile = fileURL.standardizedFileURL
            .resolvingSymlinksInPath().path
        let prefix = canonicalRoot.hasSuffix("/")
            ? canonicalRoot : canonicalRoot + "/"
        guard canonicalFile.hasPrefix(prefix) else {
            throw transferError("A Gecko profile file is outside its profile directory.")
        }
        let relative = String(canonicalFile.dropFirst(prefix.count))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty,
              !relative.contains("\\"), !relative.contains("\u{0}"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw transferError("A Gecko profile path cannot be exported safely.")
        }
        return relative
    }


    private static func validatePortableArchiveV1(
        archiveURL: URL, providerIdentifier: String
    ) throws {
        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        try validateHeader(input: input, providerIdentifier: providerIdentifier)
        var seen = Set<String>()
        var total: UInt64 = 0
        while true {
            let length = try readUInt32(from: input)
            if length == 0 { break }
            guard length <= 4096, seen.count < 100000 else {
                throw transferError("Invalid session archive.")
            }
            let size = try readUInt64(from: input)
            guard size <= 8 * 1024 * 1024 * 1024,
                  total <= 12 * 1024 * 1024 * 1024 - size else {
                throw transferError("Session archive is too large.")
            }
            total += size
            let pathData = try readExactly(Int(length), from: input)
            guard let path = String(data: pathData, encoding: .utf8),
                  !path.isEmpty, !path.hasPrefix("/"),
                  !path.contains("\\"), !path.contains("\u{0}"),
                  !path.split(separator: "/", omittingEmptySubsequences: false)
                    .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !isSQLiteSidecar(path), seen.insert(path).inserted else {
                throw transferError("Invalid file path in session archive.")
            }
            var remaining = size
            while remaining > 0 {
                let amount = Int(min(remaining, UInt64(1024 * 1024)))
                let chunk = input.readData(ofLength: amount)
                guard chunk.count == amount else {
                    throw transferError("Incomplete session archive.")
                }
                remaining -= UInt64(chunk.count)
            }
        }
        guard input.readData(ofLength: 1).isEmpty, seen.contains("LegacyRelayPortableV2.marker") else {
            throw transferError("Invalid or empty session archive.")
        }
    }

    static func stageCompatibleImport(
        archiveURL: URL, providerIdentifier: String
    ) throws {
        let safe = LegacyRelayGeckoProfile.safeIdentifier(providerIdentifier)
        guard safe == "snapchat" else {
            throw transferError("Unsupported website.")
        }
        let secured = archiveURL.startAccessingSecurityScopedResource()
        defer { if secured { archiveURL.stopAccessingSecurityScopedResource() } }
        let reader = try FileHandle(forReadingFrom: archiveURL)
        let header = reader.readData(ofLength: magic.count)
        reader.closeFile()
        if header == magic {
            try validatePortableArchiveV1(
                archiveURL: archiveURL, providerIdentifier: safe
            )
            try stageImport(archiveURL: archiveURL, providerIdentifier: safe)
            return
        }
        throw transferError(
            "This older cookie-only backup cannot be imported safely. Export a new session."
        )
    }

    private static func transferError(_ text: String) -> NSError {
        return NSError(domain: "LegacyRelay.SnapTransfer", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: text])
    }

    private static func validatedSnapCookies(_ data: Data) throws -> [[String: Any]] {
        guard data.count <= 16 * 1024 * 1024,
              let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (doc["format"] as? String) == "legacyrelay-session-v1",
              (doc["version"] as? NSNumber)?.intValue == 1,
              (doc["provider"] as? String)?.lowercased() == "snapchat",
              let cookies = doc["cookies"] as? [[String: Any]],
              !cookies.isEmpty, cookies.count <= 5000 else {
            throw transferError("Invalid Snapchat session file.")
        }
        for cookie in cookies {
            guard let name = cookie["name"] as? String,
                  let value = cookie["value"] as? String,
                  let domain = cookie["domain"] as? String,
                  !name.isEmpty, name.count < 1024, value.count < 65536,
                  !name.contains(";"), !name.contains("\n"),
                  !domain.contains("/"), !domain.contains("@"),
                  !domain.contains(":") else {
                throw transferError("Invalid Snapchat cookie.")
            }
            let host = domain.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: ".")
            )
            guard host == "snapchat.com" || host.hasSuffix(".snapchat.com") ||
                  host == "snapkit.com" || host.hasSuffix(".snapkit.com") else {
                throw transferError("Session contains unrelated cookies.")
            }
        }
        return cookies
    }

    static func applyPendingSnapCookies(
        archiveURL: URL, profileURL: URL
    ) throws {
        let cookies = try validatedSnapCookies(Data(contentsOf: archiveURL))
        guard let database = cookieDatabases(in: profileURL).first else {
            throw transferError("Snapchat cookie database not found.")
        }
        var db: OpaquePointer?
        let open = database.path.withCString {
            sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard open == SQLITE_OK, let connection = db else {
            if db != nil { sqlite3_close(db) }
            throw transferError("Unable to open cookie storage.")
        }
        defer { sqlite3_close(connection) }
        sqlite3_busy_timeout(connection, 5000)
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw transferError("Storage unavailable.") }
        let backupFolder = support.appendingPathComponent(
            "LegacyRelay/SessionBackups", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: backupFolder, withIntermediateDirectories: true, attributes: nil
        )
        let backupURL = backupFolder.appendingPathComponent(
            "snapchat-before-cookie-import-" + UUID().uuidString + ".sqlite"
        )
        var backupDB: OpaquePointer?
        let backupOpen = backupURL.path.withCString {
            sqlite3_open_v2($0, &backupDB,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        }
        guard backupOpen == SQLITE_OK, let backupConnection = backupDB else {
            if backupDB != nil { sqlite3_close(backupDB) }
            throw transferError("Could not preserve the previous session.")
        }
        guard let backupHandle = sqlite3_backup_init(
                backupConnection, "main", connection, "main"
        ) else {
            sqlite3_close(backupConnection)
            throw transferError("Could not preserve the previous session.")
        }
        let copyResult = sqlite3_backup_step(backupHandle, -1)
        let finishResult = sqlite3_backup_finish(backupHandle)
        sqlite3_close(backupConnection)
        guard copyResult == SQLITE_DONE && finishResult == SQLITE_OK else {
            throw transferError("Could not preserve the previous session.")
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: backupURL.path
        )
        var columns = Set<String>()
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(connection,
                "PRAGMA table_info(moz_cookies)", -1, &schema, nil) == SQLITE_OK,
              let info = schema else {
            throw transferError("Cookie storage format unsupported.")
        }
        while sqlite3_step(info) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(info, 1) {
                columns.insert(String(cString: UnsafeRawPointer(pointer)
                    .assumingMemoryBound(to: CChar.self)))
            }
        }
        sqlite3_finalize(info)
        let base = ["name", "value", "host", "path", "expiry",
                    "lastAccessed", "creationTime", "isSecure", "isHttpOnly"]
        guard base.allSatisfy({ columns.contains($0) }) else {
            throw transferError("Cookie storage format unsupported.")
        }
        let fields = base + (columns.contains("originAttributes") ? ["originAttributes"] : [])
        let placeholders = Array(repeating: "?", count: fields.count).joined(separator: ",")
        let sql = "INSERT INTO moz_cookies (" + fields.joined(separator: ",") +
                  ") VALUES (" + placeholders + ")"
        guard sqlite3_exec(connection, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw transferError("Cookie storage is busy.")
        }
        var committed = false
        defer { if !committed { sqlite3_exec(connection, "ROLLBACK", nil, nil, nil) } }
        let deleteSQL = "DELETE FROM moz_cookies WHERE " +
            "lower(host) IN ('snapchat.com','.snapchat.com','snapkit.com','.snapkit.com') " +
            "OR lower(host) LIKE '%.snapchat.com' OR lower(host) LIKE '%.snapkit.com'"
        guard sqlite3_exec(connection, deleteSQL, nil, nil, nil) == SQLITE_OK else {
            throw transferError("Could not update Snapchat cookies.")
        }
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &query, nil) == SQLITE_OK,
              let statement = query else {
            throw transferError("Cookie storage format unsupported.")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let now = Int64(Date().timeIntervalSince1970)
        let microseconds = now * 1000000
        var written = 0
        for cookie in cookies {
            let sessionOnly = cookie["sessionOnly"] as? Bool ?? false
            let rawExpiry = (cookie["expires"] as? NSNumber)?.int64Value ?? 0
            let expiry = sessionOnly || rawExpiry <= 0 ? now + 86400 : rawExpiry
            if expiry <= now { continue }
            let values: [String] = [
                cookie["name"] as? String ?? "",
                cookie["value"] as? String ?? "",
                cookie["domain"] as? String ?? "",
                cookie["path"] as? String ?? "/"
            ]
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (index, value) in values.enumerated() {
                let result = value.withCString {
                    sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient)
                }
                guard result == SQLITE_OK else { throw transferError("Cookie import failed.") }
            }
            let intValues: [Int64] = [expiry, microseconds, microseconds,
                    (cookie["secure"] as? Bool ?? false) ? 1 : 0,
                    (cookie["httpOnly"] as? Bool ?? false) ? 1 : 0]
            for (index, value) in intValues.enumerated() {
                guard sqlite3_bind_int64(statement, Int32(index + 5), value) == SQLITE_OK else {
                    throw transferError("Cookie import failed.")
                }
            }
            if fields.count == 10 {
                guard "".withCString({sqlite3_bind_text(statement, 10, $0, -1, transient)})
                        == SQLITE_OK else { throw transferError("Cookie import failed.") }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw transferError("Cookie import failed.")
            }
            written += 1
        }
        guard written > 0, sqlite3_exec(connection, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            throw transferError("No usable Snapchat cookies could be imported.")
        }
        committed = true
    }

    private static func writeUInt32(
        _ value: UInt32,
        to handle: FileHandle
    ) {
        let bytes: [UInt8] = [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
        handle.write(Data(bytes))
    }

    private static func writeUInt64(
        _ value: UInt64,
        to handle: FileHandle
    ) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(8)

        for shift in stride(
            from: 0,
            through: 56,
            by: 8
        ) {
            bytes.append(
                UInt8((value >> UInt64(shift)) & 0xff)
            )
        }

        handle.write(Data(bytes))
    }

    private static func readUInt32(
        from handle: FileHandle
    ) throws -> UInt32 {
        let data = try readExactly(
            4,
            from: handle
        )
        let bytes = [UInt8](data)

        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    private static func readUInt64(
        from handle: FileHandle
    ) throws -> UInt64 {
        let data = try readExactly(
            8,
            from: handle
        )
        let bytes = [UInt8](data)

        var result: UInt64 = 0

        for index in 0..<8 {
            result |= UInt64(bytes[index])
                << UInt64(index * 8)
        }

        return result
    }

    private static func readExactly(
        _ count: Int,
        from handle: FileHandle
    ) throws -> Data {
        var result = Data()

        while result.count < count {
            let chunk = handle.readData(
                ofLength: count - result.count
            )

            if chunk.isEmpty {
                throw NSError(
                    domain: "LegacyRelay.SessionArchive",
                    code: 9,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The session archive is truncated."
                    ]
                )
            }

            result.append(chunk)
        }

        return result
    }
}
