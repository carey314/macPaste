import AppKit
import SwiftUI

@MainActor
enum PoolBrand {
  static var icon: NSImage {
    if let url = Bundle.main.url(forResource: "FushiIcon", withExtension: "icns"),
       let image = NSImage(contentsOf: url) { return image }
    return NSImage(systemSymbolName: "water.waves", accessibilityDescription: "浮拾")!
  }
}

/// Feedback never becomes key, takes mouse input or exposes copied text to Notification Center.
@MainActor
final class PoolFeedback {
  static let shared = PoolFeedback()
  private var panel: PoolFeedbackPanel?
  private var dismissTask: Task<Void, Never>?

  func show(_ message: String) {
    dismissTask?.cancel()
    let panel = panel ?? PoolFeedbackPanel(
      contentRect: NSRect(x: 0, y: 0, width: 330, height: 76),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    self.panel = panel
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = NSHostingView(rootView: PoolFeedbackView(message: message))
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    panel.setFrameOrigin(NSPoint(x: frame.midX - 165, y: frame.maxY - 94))
    panel.orderFrontRegardless()
    dismissTask = Task { [weak panel] in
      try? await Task.sleep(for: .seconds(2.2))
      guard !Task.isCancelled else { return }
      panel?.orderOut(nil)
    }
  }

  func captureDemo(to url: URL) {
    guard PoolExperience.isDemo, let view = panel?.contentView else { return }
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url, options: .atomic)
  }
}

private final class PoolFeedbackPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private struct PoolFeedbackView: View {
  let message: String
  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: PoolBrand.icon).resizable().scaledToFit().frame(width: 46, height: 46)
      VStack(alignment: .leading, spacing: 3) {
        Text("浮拾").font(.system(size: 14, weight: .semibold))
        Text(message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 17).frame(width: 330, height: 76)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.4), lineWidth: 1) }
  }
}
