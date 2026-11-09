import AppKit
import Defaults
import SwiftUI

/// Presentation is inferred from real pasteboard representations; the original content stays intact.
enum PoolItemKind {
  case image
  case link(URL)
  case code
  case files([URL])
  case text

  static func kind(for item: HistoryItemDecorator) -> PoolItemKind {
    if item.hasImage { return .image }
    if item.hasFileURLs { return .files(item.item.fileURLs) }
    let text = item.item.previewableText.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
       url.host != nil, !text.contains(where: \.isWhitespace) {
      return .link(url)
    }
    if let content = item.item.contents.first(where: { $0.type == NSPasteboard.PasteboardType.URL.rawValue }),
       let data = content.value, let string = String(data: data, encoding: .utf8),
       let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
      return .link(url)
    }
    let starts = ["npm ", "pnpm ", "yarn ", "git ", "swift ", "let ", "var ", "func ",
                  "import ", "const ", "def ", "#!/", "{\n", "<html", "SELECT "]
    if starts.contains(where: text.hasPrefix) || text.contains("\n  ") || text.contains(" => ") {
      return .code
    }
    return .text
  }
}

struct PoolItemView: View {
  @Default(.poolAutoPaste) private var autoPaste
  @Bindable var item: HistoryItemDecorator
  var compact = false
  var isSelected = false
  var dragEnabled = true
  let select: () -> Void
  let copy: () -> Void
  let copyOnly: () -> Void
  let preview: () -> Void
  let togglePin: () -> Void
  let delete: () -> Void
  let dragStarted: () -> Void
  let dragEnded: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(AppState.self) private var appState
  @State private var hovering = false

  var body: some View {
    Button(action: copy) {
      PoolItemFace(item: item, compact: compact)
        .contentShape(RoundedRectangle(cornerRadius: compact ? 17 : 25))
    }
    .buttonStyle(.plain)
    .overlay {
      RoundedRectangle(cornerRadius: compact ? 17 : 25)
        .strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
        .shadow(color: .cyan.opacity(isSelected ? 0.38 : 0), radius: 9, y: 3)
        .allowsHitTesting(false)
    }
    .shadow(color: Color(red: 0.15, green: 0.27, blue: 0.37).opacity(hovering ? 0.29 : 0.18),
            radius: hovering ? 20 : 13, x: 0, y: hovering ? 15 : 9)
    .scaleEffect(hovering && !reduceMotion ? 1.025 : 1)
    .offset(y: hovering && !reduceMotion ? -5 : 0)
    .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.72), value: hovering)
    .onHover { value in
      hovering = value
      if value && dragEnabled && !appState.navigator.isDragAndDropInProgress { select() }
    }
    .modifier(PoolDragModifier(item: item, enabled: dragEnabled, started: dragStarted, ended: dragEnded))
    .contextMenu {
      Button("仅复制", systemImage: "doc.on.doc", action: copyOnly)
      Button("放大预览", systemImage: "arrow.up.left.and.arrow.down.right", action: preview)
      Divider()
      Button(item.isPinned ? "移出常用" : "放入常用", systemImage: item.isPinned ? "pin.slash" : "pin",
             action: togglePin)
        .disabled(!item.isPinned && appState.history.availablePins.isEmpty)
      Button("删除", systemImage: "trash", role: .destructive, action: delete)
    }
    .accessibilityIdentifier("pool-object-\(item.id.uuidString)")
    .accessibilityLabel(item.accessibilityLabel.isEmpty ? "剪贴板图片" : item.accessibilityLabel)
    .accessibilityHint(autoPaste ? "点击粘贴到原输入框；空格放大；可拖到其他应用或常用区"
                       : "点击复制；空格放大；可拖到其他应用或常用区")
    .accessibilityValue(item.isPinned ? "常用" : "最近复制")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityAction(named: Text("放大预览"), preview)
    .accessibilityAction(named: Text(item.isPinned ? "移出常用" : "放入常用"), togglePin)
    .accessibilityAction(named: Text("删除"), delete)
    .help(compact ? item.title : (autoPaste ? "点击粘贴 · 右键仅复制 · 拖出使用" : "点击复制 · 拖出使用 · 空格放大"))
  }
}

struct PoolItemFace: View {
  @Bindable var item: HistoryItemDecorator
  var compact = false
  @State private var poolImage: NSImage?
  private let ink = Color(red: 0.14, green: 0.18, blue: 0.23)

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let padding: CGFloat = compact ? 8 : min(22, max(10, size.height * 0.13))
      let fontSize = compact ? 11 : min(27, max(14, min(size.width / 11, size.height / 4)))
      Group {
        switch PoolItemKind.kind(for: item) {
        case .image:
          imageFace(padding: compact ? 5 : 9)
        case .link(let url):
          HStack(alignment: .center, spacing: compact ? 5 : 13) {
            appIcon(size: compact ? 23 : min(44, size.height * 0.47))
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
              Text(linkTitle(url)).font(.system(size: fontSize, weight: .medium)).lineLimit(compact ? 1 : 2)
              if !compact {
                Text(url.host ?? url.absoluteString)
                  .font(.system(size: max(11, fontSize * 0.67)))
                  .foregroundStyle(ink.opacity(0.58)).lineLimit(1)
              }
            }
            Spacer(minLength: 0)
          }
          .padding(padding)
          .background(LinearGradient(colors: [Color(red: 0.88, green: 0.97, blue: 1),
                                               Color(red: 0.59, green: 0.80, blue: 0.94)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        case .code:
          VStack(alignment: .leading, spacing: compact ? 3 : 10) {
            Image(systemName: "terminal").font(.system(size: compact ? 12 : 18))
              .foregroundStyle(.white.opacity(0.85))
            Text(item.item.previewableText.prefix(500))
              .font(.system(size: compact ? 11 : min(21, fontSize), design: .monospaced))
              .lineLimit(compact ? 2 : 5).frame(maxWidth: .infinity, alignment: .leading)
          }
          .foregroundStyle(.white.opacity(0.95)).padding(padding)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .background(LinearGradient(colors: [Color(red: 0.34, green: 0.38, blue: 0.43),
                                               Color(red: 0.19, green: 0.22, blue: 0.27)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        case .files(let urls):
          HStack(spacing: compact ? 5 : 13) {
            if let url = urls.first {
              Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                .frame(width: compact ? 24 : min(49, size.height * 0.5),
                       height: compact ? 26 : min(56, size.height * 0.56))
            }
            VStack(alignment: .leading, spacing: 5) {
              Text(urls.first?.lastPathComponent ?? "文件")
                .font(.system(size: fontSize * 0.82, weight: .medium)).lineLimit(compact ? 2 : 3)
              if !compact && urls.count > 1 {
                Text("共 \(urls.count) 个文件").font(.system(size: 12)).foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 0)
          }
          .padding(padding)
          .background(LinearGradient(colors: [.white, Color(red: 0.90, green: 0.93, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        case .text:
          let short = item.item.previewableText.count < 24 && size.height < 110
          VStack(alignment: .leading, spacing: compact ? 4 : 14) {
            if !compact && size.height > 110 { appIcon(size: min(38, size.height * 0.25)) }
            Text(item.attributedTitle ?? AttributedString(item.item.previewableText.prefix(500)))
              .font(.system(size: fontSize, weight: .medium))
              .lineLimit(compact ? 3 : max(1, Int(size.height / (fontSize * 1.35)) - 1))
              .frame(maxWidth: .infinity, alignment: short ? .center : .leading)
          }
          .padding(padding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .background(LinearGradient(colors: short
                                     ? [Color(red: 1, green: 0.96, blue: 0.79),
                                        Color(red: 0.99, green: 0.88, blue: 0.62)]
                                     : [Color(red: 1, green: 0.99, blue: 0.96),
                                        Color(red: 0.92, green: 0.90, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
      }
      .foregroundStyle(ink)
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: compact ? 17 : min(26, size.height * 0.24)))
      .overlay {
        RoundedRectangle(cornerRadius: compact ? 17 : min(26, size.height * 0.24))
          .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .white.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)
          .allowsHitTesting(false)
      }
    }
    .task(id: item.id) {
      guard let image = item.item.image else { return }
      poolImage = PoolRasterImage.thumbnail(image, maximumDimension: compact ? 220 : 720)
    }
    .onDisappear {
      poolImage = nil
      item.item.clearDecodedImageCache()
    }
  }

  private func appIcon(size: CGFloat) -> some View {
    Image(nsImage: item.applicationImage.nsImage).resizable().scaledToFit().frame(width: size, height: size)
      .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
      .accessibilityHidden(true)
  }

  private func linkTitle(_ url: URL) -> String {
    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if title != url.absoluteString, !title.isEmpty { return title }
    return url.lastPathComponent.isEmpty ? (url.host ?? "网页链接") : url.lastPathComponent.removingPercentEncoding ?? "网页链接"
  }

  private func imageFace(padding: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: compact ? 17 : 26).fill(.ultraThinMaterial)
      if let image = poolImage ?? item.item.image {
        GeometryReader { geometry in
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 19))
        .overlay {
          RoundedRectangle(cornerRadius: compact ? 12 : 19).strokeBorder(.white.opacity(0.7), lineWidth: 1)
        }
        .padding(padding)
      } else {
        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
      }
    }
  }
}


/// A real bitmap owns only its bounded pixel buffer. NSImage's drawing-handler
/// resize would keep the full source image alive through a captured closure.
enum PoolRasterImage {
  static func thumbnail(_ source: NSImage, maximumDimension: CGFloat) -> NSImage? {
    guard source.size.width > 0, source.size.height > 0 else { return nil }
    let ratio = min(1, maximumDimension / max(source.size.width, source.size.height))
    let width = max(1, Int((source.size.width * ratio).rounded()))
    let height = max(1, Int((source.size.height * ratio).rounded()))
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
  }
}
