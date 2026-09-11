import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import AppKit

final class DraggableBarView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isMovableByWindowBackground = true
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableBarView { DraggableBarView() }
    func updateNSView(_ nsView: DraggableBarView, context: Context) {}
}

// AppKit-level drag source: SwiftUI's `.onDrag` can only carry a single file,
// so multi-file copy is started here with one NSDraggingItem per selected URL.
final class DragSourceView: NSView, NSDraggingSource {
    var paths: [String] = []
    var dragImage: NSImage?
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    private var mouseDownEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let dx = abs(event.locationInWindow.x - down.locationInWindow.x)
        let dy = abs(event.locationInWindow.y - down.locationInWindow.y)
        if dx > 3 || dy > 3 {
            mouseDownEvent = nil
            beginDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let didDrag = mouseDownEvent == nil
        mouseDownEvent = nil
        guard !didDrag else { return }
        // A mouse selection should also make the timeline the keyboard target.
        window?.makeFirstResponder(self)
        if event.clickCount >= 2 { onOpen?() } else { onSelect?() }
    }

    private func beginDrag(with event: NSEvent) {
        let urls = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        var items: [NSDraggingItem] = []
        for (index, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: index == 0 ? dragContents(count: urls.count) : nil)
            items.append(item)
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    private func dragContents(count: Int) -> NSImage? {
        guard let base = dragImage else { return nil }
        if count <= 1 { return base }
        let size = base.size
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        let side = min(size.width, size.height) * 0.36
        let badge = NSRect(x: size.width - side - 2, y: 2, width: side, height: side)
        NSColor.red.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let text = NSAttributedString(string: "\(count)", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: side * 0.55, weight: .semibold)
        ])
        let textSize = text.size()
        text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

struct DragSource: NSViewRepresentable {
    let paths: [String]
    let image: NSImage?
    let onSelect: () -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.paths = paths
        nsView.dragImage = image
        nsView.onSelect = onSelect
        nsView.onOpen = onOpen
    }
}

// Decode only bounded thumbnails, serially off the main thread; retained pixels are capped.
actor Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 96 * 1024 * 1024; cache.countLimit = 480 }
    func load(_ path: String) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: path as NSString) { return image }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary), !Task.isCancelled else { return nil }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            cache.setObject(image, forKey: path as NSString, cost: cg.bytesPerRow * cg.height)
            return image
        }
    }
}

struct PhotoTile: View {
    let item: IndexedImage
    let selected: Bool
    let size: CGSize
    let dragPaths: [String]
    let select: () -> Void
    let open: () -> Void
    let onDelete: ([String]) -> Void
    @State private var image: NSImage?
    @State private var hovering = false
    @State private var unavailable = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(.quaternary.opacity(0.35))
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else if unavailable {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(item.date.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
            .opacity(hovering || selected ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: hovering || selected)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.accentColor, .white)
                    .font(.system(size: 17, weight: .semibold))
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .padding(7)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .overlay { DragSource(paths: dragPaths, image: image, onSelect: select, onOpen: open).onHover { hovering = $0 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.tr("\(URL(fileURLWithPath: item.path).lastPathComponent)，\(item.date.formatted(date: .abbreviated, time: .shortened))", "\(URL(fileURLWithPath: item.path).lastPathComponent), \(item.date.formatted(date: .abbreviated, time: .shortened))"))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(L.tr("点按选择，拖移可复制或移动，右键查看操作", "Click to select, drag to copy or move, right-click for actions"))
        .accessibilityAction(named: L.tr("打开", "Open")) { PhotoActions.open(item.path) }
        .accessibilityAction(named: L.tr("快速查看", "Quick Look")) { PhotoActions.quickLook([item.path]) }
        .accessibilityAction(named: L.tr("在访达中显示", "Show in Finder")) { PhotoActions.reveal([item.path]) }
        .accessibilityAction(named: L.tr("复制", "Copy")) { PhotoActions.copy([item.path]) }
        .accessibilityAction(named: L.tr("移到废纸篓", "Move to Trash")) { onDelete([item.path]) }
        .contextMenu {
            Button(L.tr("打开", "Open")) { PhotoActions.open(item.path) }
            Button(L.tr("快速查看", "Quick Look")) { PhotoActions.quickLook([item.path]) }
            Button(L.tr("在访达中显示", "Show in Finder")) { PhotoActions.reveal([item.path]) }
            Button(L.tr("复制", "Copy")) { PhotoActions.copy([item.path]) }
            Divider()
            Button(L.tr("移到废纸篓", "Move to Trash"), role: .destructive) { onDelete([item.path]) }
        }
        .task(id: item.path) {
            let result = await Thumbnails.shared.load(item.path)
            guard !Task.isCancelled else { return }
            image = result; unavailable = result == nil
        }
        .onDisappear { image = nil; hovering = false }
    }
}
struct PhotoRow: Identifiable {
    var id: String { items[0].path }
    let items: [IndexedImage]
    let height: CGFloat
}
struct PhotoDay: Identifiable {
    var id: Date { date }
    let date: Date
    let rows: [PhotoRow]
    var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L.tr("今天", "Today") }
        if calendar.isDateInYesterday(date) { return L.tr("昨天", "Yesterday") }
        return date.formatted(.dateTime.year().month().day())
    }
}

enum TimelineEntry: Identifiable {
    case header(PhotoDay)
    case row(day: Date, row: PhotoRow)

    var id: String {
        switch self {
        case .header(let day):
            return "header-\(day.date.timeIntervalSinceReferenceDate)"
        case .row(_, let row):
            return "row-\(row.id)"
        }
    }
}

enum TimelineLayout {
    static func ratio(_ item: IndexedImage) -> CGFloat { CGFloat(item.width) / CGFloat(max(1, item.height)) }
    static func days(_ items: [IndexedImage], width: CGFloat, target: CGFloat) -> [PhotoDay] {
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { date in
            var rows: [PhotoRow] = [], pending: [IndexedImage] = []
            var sum: CGFloat = 0
            for item in groups[date, default: []] {
                pending.append(item); sum += ratio(item)
                if sum * target + CGFloat(pending.count - 1) * 8 >= width {
                    rows.append(PhotoRow(items: pending, height: max(1, (width - CGFloat(pending.count - 1) * 8) / sum)))
                    pending = []; sum = 0
                }
            }
            if !pending.isEmpty { rows.append(PhotoRow(items: pending, height: min(target, (width - CGFloat(pending.count - 1) * 8) / sum))) }
            return PhotoDay(date: date, rows: rows)
        }
    }

    static func entries(_ days: [PhotoDay]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        entries.reserveCapacity(days.reduce(0) { $0 + $1.rows.count + 1 })
        for day in days {
            entries.append(.header(day))
            entries.append(contentsOf: day.rows.map { .row(day: day.date, row: $0) })
        }
        return entries
    }
}
private struct DayAnchorKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]
    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TimelineHeader: View {
    let day: PhotoDay

    var body: some View {
        HStack(spacing: 14) {
            Text(day.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Rectangle().fill(.separator).frame(height: 0.5)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct TimelineRow: View {
    let row: PhotoRow
    let selection: Set<String>
    let selectedPaths: [String]
    let select: (IndexedImage) -> Void
    let open: (IndexedImage) -> Void
    let onDelete: ([String]) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(row.items) { item in
                PhotoTile(item: item,
                          selected: selection.contains(item.path),
                          size: CGSize(width: TimelineLayout.ratio(item) * row.height, height: row.height),
                          dragPaths: selection.contains(item.path) ? selectedPaths : [item.path],
                          select: { select(item) },
                          open: { open(item) },
                          onDelete: onDelete)
                    .frame(width: TimelineLayout.ratio(item) * row.height, height: row.height)
            }
        }
        .frame(height: row.height)
    }
}

private struct RingRail: View {
    let years: [Int]
    let activeYear: Int?
    let activeMonth: Int
    let onTapYear: (Int) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.separator)
                .frame(width: 0.5)
            VStack(spacing: 0) {
                ForEach(years, id: \.self) { year in
                    Spacer(minLength: 18)
                    YearRailCell(year: year,
                                 active: year == activeYear,
                                 activeMonth: year == activeYear ? activeMonth : nil,
                                 onTap: { onTapYear(year) })
                    Spacer(minLength: 18)
                }
            }
            .padding(.vertical, 6)
        }
        .animation(.easeInOut(duration: 0.18), value: activeYear)
        .animation(.easeInOut(duration: 0.18), value: activeMonth)
    }
}

private struct YearRailCell: View {
    let year: Int
    let active: Bool
    let activeMonth: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Circle()
                    .fill(active ? Color.accentColor : Color.secondary.opacity(0.42))
                    .frame(width: active ? 8 : 5, height: active ? 8 : 5)
                Text(String(year))
                    .font(.system(size: 10, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if let activeMonth {
                    Text(L.tr("\(activeMonth)月", "\(activeMonth)"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 54)
            .frame(minHeight: 50)
            .background(active ? Color.accentColor.opacity(0.10) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.tr("跳至 \(year) 年", "Jump to \(year)"))
    }
}

struct LibraryView: View {
    @ObservedObject var library: Library
    @State private var anchor: String?
    @State private var layoutEntries: [TimelineEntry] = []
    @State private var layoutKey = ""
    @State private var activeYear: Int?
    @State private var activeMonth: Int = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var escapeMonitor: Any?
    private func select(_ item: IndexedImage) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor, let first = library.images.firstIndex(where: { $0.path == anchor }), let last = library.images.firstIndex(where: { $0.path == item.path }) {
            library.selection = Set(library.images[min(first,last)...max(first,last)].map(\.path))
        } else if flags.contains(.command) {
            if library.selection.contains(item.path) { library.selection.remove(item.path) } else { library.selection.insert(item.path) }
            anchor = item.path
        } else { library.selection = [item.path]; anchor = item.path }
    }
    private func cacheLayout(key: String, width: CGFloat) {
        guard layoutKey != key else { return }
        let days = TimelineLayout.days(library.images, width: width, target: [110.0, 165.0, 230.0][library.density])
        layoutEntries = TimelineLayout.entries(days)
        layoutKey = key
    }
    private func updateActive(_ anchors: [Date: CGFloat]) {
        guard !anchors.isEmpty else { return }
        let top = anchors.min(by: { abs($0.value) < abs($1.value) })!.key
        let calendar = Calendar.current
        let year = calendar.component(.year, from: top)
        let month = calendar.component(.month, from: top)
        if year != activeYear { activeYear = year }
        if month != activeMonth { activeMonth = month }
    }
    private func openLegacySettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    private func scrollToYear(_ year: Int) {
        guard let image = library.images.filter({ Calendar.current.component(.year, from: $0.date) == year }).max(by: { $0.date < $1.date }) else { return }
        let target = Calendar.current.startOfDay(for: image.date)
        withAnimation(.easeInOut(duration: 0.35)) { scrollProxy?.scrollTo(target, anchor: .top) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if library.scanning {
                HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(library.status).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 24).padding(.vertical, 6)
            }
            if !library.hasConfiguredSource {
                EmptyLibraryState(addFolder: library.chooseFolders)
            } else if library.images.isEmpty && !library.scanning {
                VStack(spacing: 12) {
                    Text(L.tr("这段时间还没有图片", "No images in this period yet")).font(.headline)
                    Text(L.tr("选择其他时间范围，或添加图片所在的目录。", "Choose another time range, or add the folder that contains your images.")).foregroundStyle(.secondary)
                    Button(L.tr("添加目录…", "Add Folder…"), action: library.chooseFolders)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let railWidth: CGFloat = 76
                    let width = max(1, geometry.size.width - railWidth - 48)
                    let key = "\(library.revision)|\(library.range)|\(library.density)|\(Int(width))"
                    let entries = layoutKey == key
                        ? layoutEntries
                        : TimelineLayout.entries(TimelineLayout.days(library.images, width: width, target: [110.0, 165.0, 230.0][library.density]))
                    let draggedPaths = library.selection.sorted()
                    HStack(spacing: 0) {
                        RingRail(years: library.years, activeYear: activeYear, activeMonth: activeMonth, onTapYear: { scrollToYear($0) })
                            .frame(minWidth: railWidth, maxWidth: railWidth, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.05))
                            .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 0.5) }
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(entries) { entry in
                                        switch entry {
                                        case .header(let day):
                                            TimelineHeader(day: day)
                                                .id(day.id)
                                                .background(GeometryReader { inner in
                                                    Color.clear.preference(key: DayAnchorKey.self, value: [day.date: inner.frame(in: .named("timeline")).minY])
                                                })
                                        case .row(_, let row):
                                            TimelineRow(row: row,
                                                        selection: library.selection,
                                                        selectedPaths: draggedPaths,
                                                        select: select,
                                                        open: { PhotoActions.open($0.path) },
                                                        onDelete: library.deleteImages)
                                                .padding(.bottom, 12)
                                        }
                                    }
                                }
                                .padding(.horizontal, 24).padding(.bottom, 24)
                            }
                            .id(library.range)
                            .coordinateSpace(name: "timeline")
                            .onPreferenceChange(DayAnchorKey.self) { updateActive($0) }
                            .onChange(of: library.range) { _ in
                                library.selection = []
                                anchor = nil
                            }
                            .onChange(of: key) { newKey in cacheLayout(key: newKey, width: width) }
                            .onAppear {
                                scrollProxy = proxy
                                cacheLayout(key: key, width: width)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !library.selection.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(Color.accentColor)
                    Text(L.selectedCount(library.selection.count))
                        .font(.callout.weight(.medium))
                    Text("·").foregroundStyle(.tertiary)
                    Text(library.selection.count == 1 ? L.tr("空格快速查看  ·  ⌘C 复制  ·  ↩ 在访达中显示", "Space to preview  ·  ⌘C to copy  ·  ↩ to show in Finder") : library.selectionSpan)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(L.tr("取消选择", "Deselect")) { library.clearSelection() }
                        .buttonStyle(.link)
                    Button(role: .destructive) {
                        library.deleteSelection()
                    } label: {
                        Label(L.tr("批量删除", "Delete Selected"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(L.tr("批量删除所选图片", "Delete selected images"))
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .top) { Rectangle().fill(.separator).frame(height: 0.5) }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowDragArea())
        .animation(.easeInOut(duration: 0.2), value: library.selection.count)
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 16) {
                    TimelineRangeButton(title: L.tr("今天", "Today"), value: "Today", selection: $library.range)
                    TimelineRangeButton(title: L.tr("7天", "7 Days"), value: "7D", selection: $library.range)
                    TimelineRangeButton(title: L.tr("30天", "30 Days"), value: "30D", selection: $library.range)
                    TimelineRangeButton(title: L.tr("全部", "All"), value: "All", selection: $library.range)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 10) {
                    Text(L.imageCount(library.images.count))
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .accessibilityLabel(L.imageCount(library.images.count))
                    if #available(macOS 14.0, *) {
                        SettingsLink {
                            Image(systemName: "gearshape")
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help(L.tr("设置", "Settings"))
                        .accessibilityLabel(L.tr("设置", "Settings"))
                    } else {
                        Button(action: openLegacySettings) {
                            Image(systemName: "gearshape")
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help(L.tr("设置", "Settings"))
                        .accessibilityLabel(L.tr("设置", "Settings"))
                    }
                }
            }
        }
        .onAppear {
            if escapeMonitor == nil {
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53, !library.selection.isEmpty {
                        library.clearSelection()
                        return nil
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
    }
}

private struct EmptyLibraryState: View {
    let addFolder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(L.tr("图片时间线", "Photo timeline"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(L.tr("从一个文件夹开始", "Start with a folder"))
                        .font(.system(size: 23, weight: .semibold))
                    Text(L.tr("选择图片所在的文件夹，Picrow 会按真实创建时间整理。", "Choose a folder of images. Picrow will arrange them by their original creation time."))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }

            Button(action: addFolder) {
                Label(L.tr("添加文件夹…", "Add Folder…"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text(L.tr("原始图片始终留在本机。", "Your original images always stay on this Mac."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
}

private struct TimelineRangeButton: View {
    let title: String
    let value: String
    @Binding var selection: String

    var body: some View {
        Button { selection = value } label: {
            Text(title)
                .font(.system(size: 11, weight: selection == value ? .semibold : .regular))
                .foregroundStyle(selection == value ? .primary : .tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help(L.tr("显示\(title)的图片", "Show images from \(title)"))
    }
}

struct SettingsSheet: View {
    @ObservedObject var library: Library
    @State private var locationSheet: LocationSheet?
    @State private var showingPrivacyPolicy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.tr("设置", "Settings"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 24)

            SettingsSection(title: L.tr("浏览", "Browse")) {
                SettingsRow(label: L.tr("浏览密度", "Density")) {
                    Picker(L.tr("浏览密度", "Density"), selection: $library.density) {
                        Text(L.tr("小", "Small")).tag(0)
                        Text(L.tr("中", "Medium")).tag(1)
                        Text(L.tr("大", "Large")).tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
                }
                SettingsRow(label: L.tr("快捷键", "Shortcuts")) {
                    Text("⌘ +  /  ⌘ −")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
                }
            }

            SettingsDivider()

            SettingsSection(title: L.tr("图库", "Library")) {
                SettingsRow(label: L.tr("包含的位置", "Included Locations")) {
                    Button(L.tr("管理…", "Manage…")) { locationSheet = .included }
                        .buttonStyle(.link)
                }
                SettingsRow(label: L.tr("忽略的位置", "Ignored Locations")) {
                    Button(L.tr("管理…", "Manage…")) { locationSheet = .ignored }
                        .buttonStyle(.link)
                }
            }

            SettingsDivider()

            SettingsSection(title: L.tr("隐私", "Privacy")) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.tr("你的图片始终留在这台 Mac 上。", "Your images always stay on this Mac."))
                        Text(L.tr("Picrow 不移动、修改或上传原始图片。", "Picrow does not move, modify, or upload original images."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(L.tr("查看隐私政策…", "View Privacy Policy…")) {
                    showingPrivacyPolicy = true
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, 28)
        .frame(width: SettingsMetrics.width, alignment: .leading)
        .sheet(item: $locationSheet) { sheet in
            LocationManagementSheet(library: library, kind: sheet)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

private enum LocationSheet: String, Identifiable {
    case included
    case ignored
    var id: String { rawValue }
}

private enum SettingsMetrics {
    static let width: CGFloat = 434
    static let horizontalPadding: CGFloat = 24
    static let labelWidth: CGFloat = 128
    static let controlWidth: CGFloat = 180
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
            content
                .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 22)
    }
}

private struct LocationManagementSheet: View {
    @ObservedObject var library: Library
    let kind: LocationSheet
    @Environment(\.dismiss) private var dismiss

    private var locations: [FolderRecord] {
        kind == .included ? library.folders : library.ignoredFolders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind == .included ? L.tr("包含的位置", "Included Locations") : L.tr("忽略的位置", "Ignored Locations"))
                .font(.title3.weight(.semibold))
                .padding(.bottom, 6)
            if kind == .ignored {
                Text(L.tr("以下位置中的图片不会出现在 Picrow 中", "Images in these locations will not appear in Picrow"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)
            }
            if locations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(kind == .included ? L.tr("暂无包含位置", "No included locations") : L.tr("暂无忽略位置", "No ignored locations"))
                        .font(.headline)
                    Text(kind == .included ? L.tr("添加文件夹后，图片会出现在 Picrow 中。", "Add a folder to show its images in Picrow.") : L.tr("添加文件夹后，图片会立即从时间线中排除。", "Add a folder to keep its images out of the timeline."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(locations) { location in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                    .lineLimit(1)
                                if let path = library.path(for: location, ignored: kind == .ignored) {
                                    Text(path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer(minLength: 8)
                            Button {
                                if kind == .included { library.removeIncludedFolder(location.id) }
                                else { library.removeIgnoredFolder(location.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(L.tr("删除此位置", "Remove this location"))
                            .accessibilityLabel(L.tr("删除 \(location.name)", "Remove \(location.name)"))
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
            HStack {
                Button {
                    if kind == .included { library.chooseFolders() }
                    else { library.chooseIgnoredFolders() }
                } label: {
                    Label(L.tr("添加文件夹", "Add Folder"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(L.tr("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 500, height: 360)
    }
}
