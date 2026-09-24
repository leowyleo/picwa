import Foundation
import ImageIO
import CSQLite

struct IndexedImage: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let width: Int
    let height: Int
    let date: Date
}
struct Snapshot: Sendable {
    let count: Int
    let samples: [IndexedImage]
}
struct ScanResult: Sendable {
    let indexed: Int
    let skipped: Int
    let errors: Int
}
struct IndexFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// One actor owns SQLite and filesystem enumeration. UI never performs indexing.
actor ImageIndex {
    private var db: OpaquePointer?
    private let url: URL
    init(url: URL) { self.url = url }
    private func connect() throws {
        guard db == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw failure() }
        try execute("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS images(path TEXT PRIMARY KEY, folder TEXT NOT NULL, width INTEGER, height INTEGER, timeline REAL, observed REAL, modified REAL); CREATE INDEX IF NOT EXISTS image_time ON images(timeline DESC);")
    }
    private func failure() -> IndexFailure {
        IndexFailure(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? L.tr("无法打开本地索引", "Unable to open the local index"))
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    func needsTimelineRefresh() throws -> Bool {
        try connect()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }
        return sqlite3_column_int(stmt, 0) < 2
    }
    func markTimelineRefreshDone() throws {
        try connect()
        try execute("PRAGMA user_version = 2")
    }
    private func bind(_ value: String, to stmt: OpaquePointer?, at index: Int32) {
        value.withCString { p in _ = sqlite3_bind_text(stmt, index, p, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    func snapshot(folders folderRoots: [String]? = nil) throws -> Snapshot {
        try connect()
        if let folderRoots, folderRoots.isEmpty { return Snapshot(count: 0, samples: []) }
        let filter = folderRoots.map { roots in
            " WHERE folder IN (" + roots.map { _ in "?" }.joined(separator: ",") + ")"
        } ?? ""
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM images\(filter)", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        if let folderRoots {
            for (index, root) in folderRoots.enumerated() { bind(root, to: stmt, at: Int32(index + 1)) }
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { sqlite3_finalize(stmt); throw failure() }
        let count = Int(sqlite3_column_int64(stmt, 0)); sqlite3_finalize(stmt)
        guard sqlite3_prepare_v2(db, "SELECT path,width,height,timeline FROM images\(filter) ORDER BY timeline DESC, path ASC", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        if let folderRoots {
            for (index, root) in folderRoots.enumerated() { bind(root, to: stmt, at: Int32(index + 1)) }
        }
        defer { sqlite3_finalize(stmt) }
        var samples: [IndexedImage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            samples.append(IndexedImage(path: path, width: Int(sqlite3_column_int(stmt, 1)), height: Int(sqlite3_column_int(stmt, 2)), date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))))
        }
        return Snapshot(count: count, samples: samples)
    }

    func remove(paths: [String]) throws {
        try connect()
        guard !paths.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM images WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
            defer { sqlite3_finalize(stmt) }
            for path in paths {
                sqlite3_reset(stmt); sqlite3_clear_bindings(stmt)
                bind(path, to: stmt, at: 1)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func removeFolder(_ folder: URL) throws {
        try connect()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM images WHERE folder = ? OR path = ? OR substr(path, 1, length(?)) = ?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        bind(folder.path, to: stmt, at: 1)
        bind(folder.path, to: stmt, at: 2)
        let prefix = folder.path == "/" ? "/" : folder.path + "/"
        bind(prefix, to: stmt, at: 3)
        bind(prefix, to: stmt, at: 4)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }

    @discardableResult
    func pruneMissing() throws -> Int {
        try connect()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path FROM images", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var missing: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            if !FileManager.default.fileExists(atPath: path) { missing.append(path) }
        }
        guard !missing.isEmpty else { return 0 }
        try execute("BEGIN IMMEDIATE")
        do {
            var del: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM images WHERE path = ?", -1, &del, nil) == SQLITE_OK else { throw failure() }
            defer { sqlite3_finalize(del) }
            for path in missing {
                sqlite3_reset(del); sqlite3_clear_bindings(del)
                bind(path, to: del, at: 1)
                guard sqlite3_step(del) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        return missing.count
    }

    func scan(_ folder: URL, ignoring ignoredPaths: Set<String> = [], visibleFolders: [String]? = nil, batch: (@Sendable (Snapshot) -> Void)? = nil, progress: @escaping @Sendable (Int) -> Void) throws -> ScanResult {
        try connect()
        guard FileManager.default.isReadableFile(atPath: folder.path) else { throw IndexFailure(message: L.tr("目录无法访问，请重新连接：\(folder.lastPathComponent)", "Folder is unavailable. Please reconnect: \(folder.lastPathComponent)")) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]
        var errors = 0
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in errors += 1; return true }) else { throw IndexFailure(message: L.tr("无法读取目录", "Unable to read the folder")) }
        let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "tiff", "bmp"]
        var stmt: OpaquePointer?
        let sql = "INSERT INTO images(path,folder,width,height,timeline,observed,modified) VALUES(?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET folder=excluded.folder,width=excluded.width,height=excluded.height,modified=excluded.modified,timeline=excluded.timeline"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var indexed = 0, skipped = 0
        var seen = Set<String>()
        var samplesByPath: [String: IndexedImage] = [:]
        var lastBatch = Date.distantPast
        if batch != nil {
            for sample in (try snapshot(folders: visibleFolders)).samples { samplesByPath[sample.path] = sample }
        }
        try execute("BEGIN IMMEDIATE")
        do {
            for case let file as URL in files {
                try Task.checkCancellation()
                let path = file.standardizedFileURL.path
                if ignoredPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { files.skipDescendants() }
                    continue
                }
                guard extensions.contains(file.pathExtension.lowercased()) else { continue }
                seen.insert(path)
                let image: (Int, Int, Date, Date)? = autoreleasepool {
                    guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true, values.isSymbolicLink != true,
                          let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let w = properties[kCGImagePropertyPixelWidth] as? Int,
                          let h = properties[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
                    let modified = values.contentModificationDate ?? Date()
                    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
                    let exifDate = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
                    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                    let tiffDate = tiff?[kCGImagePropertyTIFFDateTime] as? String
                    let captured = self.exifDate(exifDate) ?? self.exifDate(tiffDate)
                    let date = captured ?? values.creationDate ?? modified
                    return (w, h, date, modified)
                }
                guard let (w,h,date,modified) = image else { skipped += 1; continue }
                sqlite3_reset(stmt); sqlite3_clear_bindings(stmt)
                bind(file.standardizedFileURL.path, to: stmt, at: 1); bind(folder.path, to: stmt, at: 2)
                sqlite3_bind_int64(stmt, 3, Int64(w)); sqlite3_bind_int64(stmt, 4, Int64(h))
                sqlite3_bind_double(stmt, 5, date.timeIntervalSince1970); sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970); sqlite3_bind_double(stmt, 7, modified.timeIntervalSince1970)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
                indexed += 1
                if batch != nil {
                    samplesByPath[file.standardizedFileURL.path] = IndexedImage(path: file.standardizedFileURL.path, width: w, height: h, date: date)
                }
                if indexed % 100 == 0 {
                    try execute("COMMIT")
                    progress(indexed)
                    if batch != nil {
                        let now = Date()
                        if now.timeIntervalSince(lastBatch) >= 0.6 || indexed % 1000 == 0 {
                            lastBatch = now
                            batch?(makeSnapshot(samplesByPath))
                        }
                    }
                    try execute("BEGIN IMMEDIATE")
                }
            }
            try execute("COMMIT"); progress(indexed)
            try deleteStale(folder: folder, keeping: seen)
        } catch { try? execute("ROLLBACK"); throw error }
        return ScanResult(indexed: indexed, skipped: skipped, errors: errors)
    }

    private func makeSnapshot(_ samplesByPath: [String: IndexedImage]) -> Snapshot {
        let sorted = samplesByPath.values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.path < $1.path
        }
        return Snapshot(count: sorted.count, samples: sorted)
    }

    private func exifDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let parts = string.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let dateParts = parts[0].split(separator: ":")
        let timeParts = parts[1].split(separator: ":")
        guard dateParts.count == 3, timeParts.count >= 2,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]),
              let hour = Int(timeParts[0]), let minute = Int(timeParts[1]) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        components.second = timeParts.count > 2 ? Int(timeParts[2]) : 0
        return components.date
    }

    private func deleteStale(folder: URL, keeping seen: Set<String>) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT path FROM images WHERE folder = ?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        bind(folder.path, to: stmt, at: 1)
        var gone: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            if !seen.contains(path) { gone.append(path) }
        }
        guard !gone.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            var del: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM images WHERE path = ?", -1, &del, nil) == SQLITE_OK else { throw failure() }
            defer { sqlite3_finalize(del) }
            for path in gone {
                try Task.checkCancellation()
                sqlite3_reset(del); sqlite3_clear_bindings(del)
                bind(path, to: del, at: 1)
                guard sqlite3_step(del) == SQLITE_DONE else { throw failure() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
