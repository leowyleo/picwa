import SwiftUI
import AppKit
import CoreServices

private final class FolderWatcherCallbackBox {
    weak var watcher: FolderWatcher?
    init(_ watcher: FolderWatcher) { self.watcher = watcher }
}

final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onEvent: () -> Void
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "tiff", "bmp"]
    init(path: String, onEvent: @escaping () -> Void) {
        self.onEvent = onEvent
        let box = FolderWatcherCallbackBox(self)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { (info: UnsafeRawPointer?) -> UnsafeRawPointer? in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<FolderWatcherCallbackBox>.fromOpaque(info).retain().toOpaque())
            },
            release: { (info: UnsafeRawPointer?) -> Void in
                guard let info else { return }
                Unmanaged<FolderWatcherCallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info, numEvents > 0 else { return }
            let box = Unmanaged<FolderWatcherCallbackBox>.fromOpaque(info).takeUnretainedValue()
            guard let watcher = box.watcher else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            guard watcher.shouldTrigger(for: paths) else { return }
            watcher.onEvent()
        }
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagFileEvents)) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }
    private func shouldTrigger(for paths: [String]) -> Bool {
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext) { return true }
        }
        return false
    }
    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

struct FolderRecord: Codable, Identifiable {
    let id: UUID
    var name: String
    var bookmark: Data
    var complete: Bool
}
private struct LibrarySettings: Codable {
    var ignoredFolders: [FolderRecord]
}

@MainActor final class Library: ObservableObject {
    @Published var folders: [FolderRecord] = []
    @Published var ignoredFolders: [FolderRecord] = []
    @Published var snapshot = Snapshot(count: 0, samples: [])
    @Published var status = ""
    @Published var issues: [String] = []
    @Published var scanning = false
    @Published var density: Int
    @Published var range = "All" {
        didSet {
            guard range != oldValue else { return }
            selection = []
            rebuildDerived()
        }
    }
    @Published var selection = Set<String>() {
        didSet { updateSelectionSpan() }
    }
    @Published private(set) var images: [IndexedImage] = []
    @Published private(set) var years: [Int] = []
    @Published private(set) var selectionSpan = ""
    @Published private(set) var revision = 0
    private var access: [UUID: URL] = [:]
    private var task: Task<Void, Never>?
    private var scanGeneration = 0
    private var watchers: [UUID: FolderWatcher] = [:]
    private var rescanPending = Set<UUID>()
    private let root: URL
    private let index: ImageIndex
    private var ignoredAccess: [UUID: URL] = [:]
    init() {
        density = max(0, min(2, UserDefaults.standard.object(forKey: "Picwa.density") as? Int ?? 1))
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Picwa")
        index = ImageIndex(url: root.appendingPathComponent("index.sqlite"))
        Task { await restore() }
    }
    var hasConfiguredSource: Bool {
        folders.contains { access[$0.id] != nil }
    }
    func path(for record: FolderRecord, ignored: Bool) -> String? {
        (ignored ? ignoredAccess[record.id] : access[record.id])?.path
    }
    private var activeRecords: [FolderRecord] {
        folders
    }
    private var activePaths: [String] {
        activeRecords.compactMap { access[$0.id]?.standardizedFileURL.path }
    }
    private var ignoredPaths: Set<String> {
        Set(ignoredAccess.values.map { $0.standardizedFileURL.path })
    }
    private func save() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(folders).write(to: root.appendingPathComponent("folders.json"), options: .atomic)
        let settings = LibrarySettings(ignoredFolders: ignoredFolders)
        try JSONEncoder().encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic)
    }
    private func restore() async {
        let manifest = root.appendingPathComponent("folders.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            do { folders = try JSONDecoder().decode([FolderRecord].self, from: Data(contentsOf: manifest)) }
            catch { issues.append(L.tr("目录记录无法读取，原文件已保留：\(error.localizedDescription)", "Folder records could not be read. The original file was kept: \(error.localizedDescription)")) }
        }
        let settingsURL = root.appendingPathComponent("settings.json")
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let settings = try JSONDecoder().decode(LibrarySettings.self, from: Data(contentsOf: settingsURL))
                ignoredFolders = settings.ignoredFolders
            } catch {
                issues.append(L.tr("设置无法读取，原文件已保留：\(error.localizedDescription)", "Settings could not be read. The original file was kept: \(error.localizedDescription)"))
            }
        }
        var changed = false
        for i in folders.indices { changed = restoreAccess(for: &folders[i], into: &access) || changed }
        for i in ignoredFolders.indices { changed = restoreAccess(for: &ignoredFolders[i], into: &ignoredAccess) || changed }
        for i in folders.indices.reversed() {
            guard let url = access[folders[i].id] else { continue }
            if url.standardizedFileURL.path == "/" {
                url.stopAccessingSecurityScopedResource()
                access.removeValue(forKey: folders[i].id)
                folders.remove(at: i)
                changed = true
            }
        }
        if changed || FileManager.default.fileExists(atPath: settingsURL.path) { try? save() }
        syncWatchers()
        do {
            if try await index.needsTimelineRefresh() {
                for i in folders.indices { folders[i].complete = false }
                try await index.markTimelineRefreshDone()
                try save()
            }
        } catch { issues.append(L.tr("时间线刷新检查失败：\(error.localizedDescription)", "Timeline refresh check failed: \(error.localizedDescription)")) }
        do {
            _ = try await index.pruneMissing()
        } catch { issues.append(L.tr("索引清理失败：\(error.localizedDescription)", "Index cleanup failed: \(error.localizedDescription)")) }
        await refresh()
        startPending()
    }
    private func restoreAccess(for record: inout FolderRecord, into store: inout [UUID: URL]) -> Bool {
        var started = false
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: record.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard url.startAccessingSecurityScopedResource() else { throw IndexFailure(message: L.tr("需要重新授权", "Permission needs to be granted again")) }
            started = true
            store[record.id] = url
            let refreshed = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if stale || refreshed != record.bookmark {
                record.bookmark = refreshed
                return true
            }
            return false
        } catch {
            if started, let url = store.removeValue(forKey: record.id) { url.stopAccessingSecurityScopedResource() }
            issues.append("\(record.name)：\(error.localizedDescription)")
            return false
        }
    }
    private func cancelScan() {
        task?.cancel()
        task = nil
        scanGeneration &+= 1
        scanning = false
    }
    func adjustDensity(by step: Int) {
        let next = max(0, min(2, density + step))
        guard next != density else { return }
        density = next
        UserDefaults.standard.set(next, forKey: "Picwa.density")
    }
    func chooseFolders() {
        presentFolderPanel(
            prompt: L.tr("添加文件夹", "Add Folder"),
            message: L.tr(
                "Picwa 会扫描所选文件夹及其子文件夹中的图片。首次扫描可能需要一些时间。",
                "Picwa scans for images in the selected folder and its subfolders. The first scan may take a while."
            ),
            allowsMultipleSelection: true
        ) { [weak self] urls in
            guard let self, self.confirmBroadFolderSelection(urls) else { return }
            self.addIncludedFolders(urls)
        }
    }
    private func presentFolderPanel(
        prompt: String,
        message: String,
        allowsMultipleSelection: Bool,
        completion: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.prompt = prompt
        panel.message = message

        let finish: (NSApplication.ModalResponse) -> Void = { [weak panel] response in
            guard response == .OK, let panel else { return }
            completion(panel.urls)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
    private func confirmBroadFolderSelection(_ urls: [URL]) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let broadPaths: Set<String> = ["/Users", home]
        let selected = urls.map { $0.standardizedFileURL.path }.filter { broadPaths.contains($0) }
        guard !selected.isEmpty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.tr("这个范围可能包含很多内容", "This location may include a lot of content")
        alert.informativeText = L.tr(
            "Picwa 会递归检查所选位置中的文件夹。选择整个用户目录或个人文件夹，可能遇到 macOS 保护的位置、出现额外授权提示，并延长扫描时间。建议只选择存放照片的文件夹。",
            "Picwa checks folders recursively. Scanning all users or your home folder may reach macOS-protected locations, trigger additional permission prompts, and take longer. Choose a folder that contains your photos instead."
        )
        alert.addButton(withTitle: L.tr("继续添加", "Add This Location"))
        alert.addButton(withTitle: L.tr("取消", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func resolvedPath(for record: FolderRecord) -> String? {
        if let path = access[record.id]?.standardizedFileURL.path { return path }
        var stale = false
        return (try? URL(resolvingBookmarkData: record.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL.path
    }

    private func path(_ candidate: String, isWithin root: String) -> Bool {
        root == "/" || candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private func addIncludedFolders(_ urls: [URL]) {
        var seen = Set<String>()
        let candidates = urls
            .map { $0.standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
            .sorted {
                if $0.pathComponents.count != $1.pathComponents.count { return $0.pathComponents.count < $1.pathComponents.count }
                return $0.path < $1.path
            }

        for url in candidates {
            let candidatePath = url.path
            guard candidatePath != "/" else {
                issues.append(L.tr("不能添加 Mac 根目录，请选择具体文件夹。", "The Mac root folder cannot be added. Choose a specific folder instead."))
                continue
            }
            if let existingIndex = folders.firstIndex(where: { resolvedPath(for: $0) == candidatePath }) {
                let existing = folders[existingIndex]
                do {
                    let started = url.startAccessingSecurityScopedResource()
                    let bookmark: Data
                    do { bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
                    catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
                    folders[existingIndex] = FolderRecord(id: existing.id, name: url.lastPathComponent, bookmark: bookmark, complete: false)
                    do { try save() } catch {
                        folders[existingIndex] = existing
                        if started { url.stopAccessingSecurityScopedResource() }
                        throw error
                    }
                    if let old = access[existing.id] { old.stopAccessingSecurityScopedResource() }
                    access[existing.id] = url
                } catch { issues.append(error.localizedDescription) }
                continue
            }
            if let existing = folders.first(where: { record in
                guard let root = resolvedPath(for: record) else { return false }
                return path(candidatePath, isWithin: root)
            }) {
                if resolvedPath(for: existing) != candidatePath {
                    issues.append(L.tr(
                        "“\(url.lastPathComponent)”已包含在“\(existing.name)”中，无需重复添加。",
                        "“\(url.lastPathComponent)” is already covered by “\(existing.name)”; it doesn't need to be added separately."
                    ))
                }
                continue
            }
            if let nested = folders.first(where: { record in
                guard let existingPath = resolvedPath(for: record) else { return false }
                return path(existingPath, isWithin: candidatePath)
            }) {
                issues.append(L.tr(
                    "“\(url.lastPathComponent)”包含已添加的位置“\(nested.name)”。如需扩大扫描范围，请先移除已有位置。",
                    "“\(url.lastPathComponent)” contains the existing location “\(nested.name)”. To expand the scan, remove the existing location first."
                ))
                continue
            }
            do {
                let started = url.startAccessingSecurityScopedResource()
                let bookmark: Data
                do { bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
                catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
                let record = FolderRecord(id: UUID(), name: url.lastPathComponent, bookmark: bookmark, complete: false)
                folders.append(record)
                do { try save() } catch { if started { url.stopAccessingSecurityScopedResource() }; throw error }
                access[record.id] = url
            } catch { issues.append(error.localizedDescription) }
        }
        syncWatchers()
        startPending()
    }
    func chooseIgnoredFolders() {
        presentFolderPanel(
            prompt: L.tr("忽略这些文件夹", "Ignore These Folders"),
            message: L.tr(
                "所选文件夹及其子文件夹中的图片将从 Picwa 时间线中排除。",
                "Images in the selected folder and its subfolders will be excluded from the Picwa timeline."
            ),
            allowsMultipleSelection: true
        ) { [weak self] urls in
            self?.addIgnoredFolders(urls)
        }
    }
    private func addIgnoredFolders(_ urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !ignoredAccess.values.contains(where: { $0.standardizedFileURL == standardized }),
                  !ignoredFolders.contains(where: { record in
                      var stale = false
                      return (try? URL(resolvingBookmarkData: record.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL == standardized
                  }) else { continue }
            do {
                let started = url.startAccessingSecurityScopedResource()
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                let record = FolderRecord(id: UUID(), name: url.lastPathComponent, bookmark: bookmark, complete: true)
                ignoredFolders.append(record)
                ignoredAccess[record.id] = url
                if !started { issues.append(L.tr("忽略位置需要重新授权：\(record.name)", "Permission is needed for ignored location: \(record.name)")) }
            } catch { issues.append(error.localizedDescription) }
        }
        markActiveForRescan()
        try? save()
        startPending()
    }
    func removeIncludedFolder(_ id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let removedPath = resolvedPath(for: folders[index])
        folders.remove(at: index)
        let url = access.removeValue(forKey: id)
        url?.stopAccessingSecurityScopedResource()
        watchers[id] = nil
        if let removedPath {
            for i in folders.indices {
                guard let remainingPath = resolvedPath(for: folders[i]),
                      path(remainingPath, isWithin: removedPath) || path(removedPath, isWithin: remainingPath) else { continue }
                folders[i].complete = false
            }
        }
        try? save()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let url { try? await self.index.removeFolder(url) }
            await self.refresh()
            self.startPending()
        }
    }
    func removeIgnoredFolder(_ id: UUID) {
        guard let index = ignoredFolders.firstIndex(where: { $0.id == id }) else { return }
        ignoredFolders.remove(at: index)
        if let url = ignoredAccess.removeValue(forKey: id) { url.stopAccessingSecurityScopedResource() }
        markActiveForRescan()
        try? save()
        startPending()
    }
    private func markActiveForRescan() {
        for i in folders.indices { folders[i].complete = false }
    }
    private func markFolderForRescan(_ id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].complete = false
    }
    private func syncWatchers() {
        let activeIDs = Set(activeRecords.map(\.id))
        for (id, url) in access where activeIDs.contains(id) && watchers[id] == nil {
            let folderID = id
            watchers[id] = FolderWatcher(path: url.path) { [weak self] in
                Task { @MainActor [weak self] in self?.scheduleRescan(folderID) }
            }
        }
        for id in watchers.keys where !activeIDs.contains(id) || access[id] == nil { watchers[id] = nil }
    }
    private func scheduleRescan(_ id: UUID) {
        guard !rescanPending.contains(id) else { return }
        rescanPending.insert(id)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self else { return }
            self.rescanPending.remove(id)
            guard self.access[id] != nil, self.activeRecords.contains(where: { $0.id == id }) else { return }
            self.markFolderForRescan(id)
            self.startPending()
        }
    }
    private func refresh() async {
        do {
            snapshot = try await index.snapshot(folders: activePaths)
            rebuildDerived()
            revision &+= 1
        }
        catch { issues.append(L.tr("索引读取失败：\(error.localizedDescription)", "Failed to read the index: \(error.localizedDescription)")) }
    }
    private func rebuildDerived() {
        let calendar = Calendar.current
        let samples = snapshot.samples.filter { sample in
            let path = sample.path
            let inActiveSource = activePaths.contains { root in
                root == "/" || path == root || path.hasPrefix(root + "/")
            }
            let ignored = ignoredPaths.contains { root in
                path == root || path.hasPrefix(root + "/")
            }
            return inActiveSource && !ignored
        }
        let filtered: [IndexedImage]
        if range == "All" {
            filtered = samples
        } else {
            let start = calendar.startOfDay(for: Date())
            let days = range == "Today" ? 0 : range == "7D" ? 6 : 29
            let cutoff = calendar.date(byAdding: .day, value: -days, to: start) ?? start
            filtered = samples.filter { $0.date >= cutoff }
        }
        images = filtered
        years = Array(Set(filtered.map { calendar.component(.year, from: $0.date) })).sorted(by: >)
        updateSelectionSpan()
    }
    private func updateSelectionSpan() {
        let selected = images.filter { selection.contains($0.path) }
        guard let first = selected.min(by: { $0.date < $1.date })?.date,
              let last = selected.max(by: { $0.date < $1.date })?.date else {
            selectionSpan = ""
            return
        }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            selectionSpan = first.formatted(.dateTime.year().month().day())
        } else {
            selectionSpan = "\(first.formatted(.dateTime.year().month().day())) – \(last.formatted(.dateTime.year().month().day()))"
        }
    }
    func removeImages(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let removed = Set(paths)
        let samples = snapshot.samples.filter { !removed.contains($0.path) }
        if samples.count != snapshot.samples.count {
            snapshot = Snapshot(count: samples.count, samples: samples)
            rebuildDerived()
            revision &+= 1
        }
        Task { [weak self] in
            guard let self else { return }
            do { try await self.index.remove(paths: paths) }
            catch { self.issues.append(L.tr("索引清理失败：\(error.localizedDescription)", "Index cleanup failed: \(error.localizedDescription)")) }
        }
    }
    func clearSelection() { selection = [] }
    func clearIssues() { issues.removeAll() }
    func selectAll() { selection = Set(images.map(\.path)) }
    func copySelection() { PhotoActions.copy(Array(selection)) }
    func quickLookSelection() { PhotoActions.quickLook(Array(selection)) }
    func revealSelection() { PhotoActions.reveal(Array(selection)) }
    func deleteSelection() { deleteImages(Array(selection)) }
    func deleteImages(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let failed = PhotoActions.delete(paths)
        let succeeded = paths.filter { !failed.contains($0) }
        selection = []
        removeImages(succeeded)
        if !failed.isEmpty { issues.append(L.tr("有 \(failed.count) 个文件未能移到废纸篓。", "\(failed.count) file(s) could not be moved to the Trash.")) }
    }
    func rescan() {
        issues.removeAll()
        markActiveForRescan()
        startPending()
    }
    private func startPending() {
        guard !scanning, activeRecords.contains(where: { !$0.complete && access[$0.id] != nil }) else { return }
        scanning = true
        let generation = scanGeneration
        task = Task {
            var attempted = Set<UUID>()
            while let folder = activeRecords.first(where: { !$0.complete && access[$0.id] != nil && !attempted.contains($0.id) }) {
                attempted.insert(folder.id)
                guard let url = access[folder.id] else { continue }
                status = L.tr("正在扫描 \(folder.name)…", "Scanning \(folder.name)…")
                do {
                    let result = try await index.scan(url, ignoring: ignoredPaths, visibleFolders: activePaths, batch: { [weak self] snapshot in
                        Task { @MainActor in guard let self, generation == self.scanGeneration else { return }; self.snapshot = snapshot; self.rebuildDerived(); self.revision &+= 1 }
                    }) { [weak self] count in
                        Task { @MainActor in
                            guard let self, generation == self.scanGeneration else { return }
                            self.status = L.tr(
                                "正在扫描 \(folder.name) · 已索引 \(count) 张图片",
                                "Scanning \(folder.name) · indexed \(count) images"
                            )
                        }
                    }
                    if let i = folders.firstIndex(where: { $0.id == folder.id }) {
                        folders[i].complete = true
                    }
                    do { try save() } catch {
                        if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i].complete = false }
                        throw error
                    }
                    if result.errors > 0 {
                        issues.append(L.tr(
                            "\(folder.name)：有 \(result.errors) 处无法读取，时间线可能不完整。需要时可手动重新扫描。",
                            "\(folder.name): \(result.errors) locations could not be read, so the timeline may be incomplete. You can rescan manually."
                        ))
                    }
                    if generation == scanGeneration { await refresh() }
                } catch {
                    if !Task.isCancelled { issues.append("\(folder.name)：\(error.localizedDescription)") }
                }
            }
            if generation == scanGeneration { scanning = false; status = L.tr("索引已保存到本机", "Index saved on this Mac") }
        }
    }
}

@main struct PicwaApp: App {
    @StateObject private var library = Library()
    var body: some Scene {
        WindowGroup("Picwa") { LibraryView(library: library) }
            .defaultSize(width: 980, height: 720)
            .windowStyle(.hiddenTitleBar)
            .windowToolbarStyle(.unifiedCompact)
            .commands {
                CommandGroup(replacing: .newItem) { Button(L.tr("添加目录…", "Add Folder…"), action: library.chooseFolders).keyboardShortcut("o") }
                CommandMenu(L.tr("编辑", "Edit")) {
                    Button(L.tr("全选", "Select All"), action: library.selectAll).keyboardShortcut("a")
                    Button(L.tr("取消选择", "Deselect"), action: library.clearSelection)
                        .keyboardShortcut(.escape, modifiers: [])
                        .disabled(library.selection.isEmpty)
                    Divider()
                    Button(L.tr("复制", "Copy"), action: library.copySelection).keyboardShortcut("c")
                    Button(L.tr("快速查看", "Quick Look"), action: library.quickLookSelection).keyboardShortcut(.space, modifiers: [])
                    Button(L.tr("在访达中显示", "Show in Finder"), action: library.revealSelection).keyboardShortcut(.return, modifiers: [])
                    Divider()
                    Button(L.tr("移到废纸篓", "Move to Trash"), action: library.deleteSelection).keyboardShortcut(.delete, modifiers: [])
                }
                CommandMenu(L.tr("浏览", "Browse")) {
                    Button(L.tr("放大图片", "Zoom In"), action: { library.adjustDensity(by: 1) })
                        .keyboardShortcut("+", modifiers: .command)
                    Button(L.tr("缩小图片", "Zoom Out"), action: { library.adjustDensity(by: -1) })
                        .keyboardShortcut("-", modifiers: .command)
                }
            }
        Settings {
            SettingsSheet(library: library)
        }
    }
}
