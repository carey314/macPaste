import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PoolDrag {
  static let itemType = UTType(exportedAs: "dev.carey.shiguangpool.history-item")
  static let dropTypes: [UTType] = [itemType, .text, .image, .url, .fileURL, .pdf]

  /// Export original supported bytes, never a rendered card or its truncated label.
  static func provider(for item: HistoryItemDecorator) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = item.item.fileURLs.first?.lastPathComponent ?? String(item.title.prefix(60))
    let identifier = Data(item.id.uuidString.utf8)
    provider.registerDataRepresentation(forTypeIdentifier: itemType.identifier, visibility: .ownProcess) { completion in
      completion(identifier, nil)
      return nil
    }
    for (type, data) in representations(for: item) {
      provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
        completion(data, nil)
        return nil
      }
    }
    if let url = item.item.fileURLs.first {
      provider.registerObject(url as NSURL, visibility: .all)
      let type = UTType(filenameExtension: url.pathExtension) ?? .data
      provider.registerFileRepresentation(forTypeIdentifier: type.identifier,
                                          fileOptions: .openInPlace, visibility: .all) { completion in
        completion(url, false, nil)
        return nil
      }
    } else if case .link(let url) = PoolItemKind.kind(for: item) {
      provider.registerObject(url as NSURL, visibility: .all)
    }
    return provider
  }

  static func representations(for item: HistoryItemDecorator) -> [(String, Data)] {
    item.item.contents.compactMap { content in
      guard let data = content.value, let type = UTType(content.type),
            type.conforms(to: .text) || type.conforms(to: .image) || type.conforms(to: .url) || type == .pdf,
            type != .fileURL else { return nil }
      return (content.type, data)
    }
  }

  /// AppKit's compatibility path can export every file as its own native dragging item.
  static func pasteboardItems(for item: HistoryItemDecorator) -> [NSPasteboardItem] {
    let files = item.item.fileURLs
    if !files.isEmpty {
      return files.map { url in
        let writer = NSPasteboardItem()
        writer.setString(url.absoluteString, forType: .fileURL)
        writer.setString(url.lastPathComponent, forType: .string)
        return writer
      }
    }
    let writer = NSPasteboardItem()
    for (type, data) in representations(for: item) {
      writer.setData(data, forType: NSPasteboard.PasteboardType(type))
    }
    // Cocoa rich-text editors prefer immediate TIFF data over promised image files.
    // Keep the original PNG/TIFF representation alongside this lossless compatibility form.
    if item.hasImage, writer.data(forType: .tiff) == nil,
       let data = item.item.imageData, let image = NSImage(data: data), let tiff = image.tiffRepresentation {
      writer.setData(tiff, forType: .tiff)
    }
    if case .link(let url) = PoolItemKind.kind(for: item) {
      writer.setString(url.absoluteString, forType: .URL)
    }
    return [writer]
  }
}

struct PoolDragModifier: ViewModifier {
  let item: HistoryItemDecorator
  let enabled: Bool
  let started: () -> Void
  let ended: () -> Void

  @ViewBuilder
  func body(content: Content) -> some View {
    if !enabled {
      content
    } else if #available(macOS 26.0, *), item.item.fileURLs.count <= 1, !item.hasImage {
      content
        .onDrag {
          started()
          return PoolDrag.provider(for: item)
        } preview: {
          PoolItemFace(item: item).frame(width: 230, height: 145)
        }
        .dragConfiguration(DragConfiguration(
          operationsWithinApp: .init(allowCopy: true, allowMove: false),
          operationsOutsideApp: .init(allowCopy: true, allowMove: false)
        ))
        .onDragSessionUpdated { session in
          switch session.phase {
          case .ended, .dataTransferCompleted: ended()
          default: break
          }
        }
        .onDisappear(perform: ended)
    } else {
      // Immediate AppKit image data interoperates with Cocoa editors without a file promise.
      // This also provides completion/cancellation on older systems and multi-file drags.
      content.background {
        PoolLegacyDragSource(item: item, enabled: enabled, started: started, ended: ended)
      }
    }
  }
}

private struct PoolLegacyDragSource: NSViewRepresentable {
  let item: HistoryItemDecorator
  let enabled: Bool
  let started: () -> Void
  let ended: () -> Void

  func makeNSView(context: Context) -> PoolLegacyDragView {
    let view = PoolLegacyDragView()
    configure(view)
    return view
  }

  func updateNSView(_ view: PoolLegacyDragView, context: Context) { configure(view) }

  static func dismantleNSView(_ view: PoolLegacyDragView, coordinator: ()) { view.removeMonitor() }

  private func configure(_ view: PoolLegacyDragView) {
    view.item = item
    view.enabled = enabled
    view.started = started
    view.ended = ended
    view.installMonitor()
  }
}

private final class PoolLegacyDragView: NSView, NSDraggingSource {
  var item: HistoryItemDecorator?
  var enabled = true {
    didSet { if !enabled && !dragging { mouseDown = nil } }
  }
  var started: (() -> Void)?
  var ended: (() -> Void)?
  nonisolated(unsafe) private var monitor: Any?
  private var mouseDown: NSEvent?
  private var dragging = false

  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { removeMonitor() } else { installMonitor() }
  }

  func installMonitor() {
    guard window != nil, monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
      [weak self] event in self?.handle(event) ?? event
    }
  }

  func removeMonitor() {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    if dragging { ended?() }
    dragging = false
    mouseDown = nil
  }

  deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

  private func handle(_ event: NSEvent) -> NSEvent? {
    guard event.window == window else { return event }
    switch event.type {
    case .leftMouseDown:
      mouseDown = canStartDrag(at: event) ? event : nil
    case .leftMouseDragged:
      guard let mouseDown, !dragging, canStartDrag(at: mouseDown), let item,
            hypot(event.locationInWindow.x - mouseDown.locationInWindow.x,
                  event.locationInWindow.y - mouseDown.locationInWindow.y) >= 5 else { return event }
      dragging = true
      started?()
      let preview = previewImage(item)
      let writers = PoolDrag.pasteboardItems(for: item)
      let items = writers.enumerated().map { index, writer in
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        let offset = CGFloat(index % 4) * 5
        draggingItem.setDraggingFrame(NSRect(x: offset, y: offset, width: preview.size.width,
                                             height: preview.size.height), contents: preview)
        return draggingItem
      }
      let session = beginDraggingSession(with: items, event: event, source: self)
      session.animatesToStartingPositionsOnCancelOrFail = true
      return nil
    case .leftMouseUp:
      mouseDown = nil
    default: break
    }
    return event
  }

  private func canStartDrag(at event: NSEvent) -> Bool {
    let editorOwnsEvent: Bool
    if let editor = window?.firstResponder as? NSTextView {
      editorOwnsEvent = editor.bounds.contains(editor.convert(event.locationInWindow, from: nil))
    } else {
      editorOwnsEvent = false
    }
    return PoolInputPolicy.canBeginLegacyDrag(
      enabled: enabled, pointInsideSource: bounds.contains(convert(event.locationInWindow, from: nil)),
      textEditorOwnsEvent: editorOwnsEvent
    )
  }

  func draggingSession(_ session: NSDraggingSession,
                       sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    dragging = false
    mouseDown = nil
    // A completed export is not a copy action in Fushi's clipboard engine.
    // Cancellation and success both leave the history item intact.
    ended?()
  }

  private func previewImage(_ item: HistoryItemDecorator) -> NSImage {
    let size = NSSize(width: min(max(bounds.width, 120), 260), height: min(max(bounds.height, 70), 170))
    let hosting = NSHostingView(rootView: PoolItemFace(item: item).frame(width: size.width, height: size.height))
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    let image = NSImage(size: size)
    if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
      hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
      image.addRepresentation(bitmap)
    }
    return image
  }
}
