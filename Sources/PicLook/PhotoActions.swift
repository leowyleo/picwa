import AppKit
import Quartz
import UniformTypeIdentifiers

final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var urls: [NSURL] = []

    func show(_ paths: [String]) {
        let items = paths.compactMap { path -> NSURL? in
            FileManager.default.fileExists(atPath: path) ? NSURL(fileURLWithPath: path) : nil
        }
        guard !items.isEmpty else { return }
        urls = items
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] }
}

enum PhotoActions {
    private static func existing(_ paths: [String]) -> [URL] {
        paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func reveal(_ paths: [String]) {
        let urls = existing(paths)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func copy(_ paths: [String]) {
        let urls = existing(paths)
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        if urls.count == 1, let image = NSImage(contentsOf: urls[0]) {
            pasteboard.writeObjects([image])
        }
    }

    static func open(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @discardableResult
    static func delete(_ paths: [String]) -> [String] {
        var failed: [String] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
            } catch { failed.append(path) }
        }
        return failed
    }

    static func quickLook(_ paths: [String]) { QuickLookController.shared.show(paths) }
}
