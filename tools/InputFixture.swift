// A separate native input window for manual paste/drag QA using synthetic data only.
// Build: swiftc -parse-as-library tools/InputFixture.swift -o /tmp/FushiInputFixture
import AppKit

final class FixtureTextView: NSTextView {
  var dropRecorded: (([String], Bool) -> Void)?
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
    let accepted = super.performDragOperation(sender)
    dropRecorded?(types, accepted)
    return accepted
  }
}

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
  var window: NSWindow!
  var text: FixtureTextView!
  var dropCount = 0
  var dropTypes: [String] = []
  var dropAccepted = false
  let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let area = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    window = NSWindow(contentRect: NSRect(x: area.minX + 18, y: area.minY + 18, width: 430, height: 190),
                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "浮拾 · 合成输入测试"
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let scroll = NSScrollView(frame: NSRect(x: 16, y: 16, width: 398, height: 158))
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    text = FixtureTextView(frame: scroll.bounds)
    text.isRichText = true
    text.importsGraphics = true
    text.isEditable = true
    text.isSelectable = true
    text.textContainerInset = NSSize(width: 12, height: 12)
    text.autoresizingMask = [.width]
    text.delegate = self
    text.setAccessibilityIdentifier("fushi-fixture-input")
    text.dropRecorded = { [weak self] types, accepted in
      self?.dropCount += 1
      self?.dropTypes = types
      self?.dropAccepted = accepted
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.record() }
    }
    scroll.documentView = text
    window.contentView?.addSubview(scroll)
    let menu = NSMenu()
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let actions = NSMenu(title: "Edit")
    actions.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    actions.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    actions.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    edit.submenu = actions
    menu.addItem(edit)
    NSApp.mainMenu = menu
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(text)
    NSApp.activate(ignoringOtherApps: true)
    record()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(text)
    record()
    return true
  }

  func textDidChange(_ notification: Notification) { record() }

  func record() {
    guard let output, let text else { return }
    let visible = text.visibleRect
    let origin = text.convert(NSPoint(x: visible.minX + 25, y: visible.minY + min(40, visible.height / 2)), to: nil)
    let screenPoint = window.convertPoint(toScreen: origin)
    let top = NSScreen.screens.first?.frame.maxY ?? 900
    var attachments = 0
    text.textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.string.utf16.count)) { value, _, _ in
      if value is NSTextAttachment { attachments += 1 }
    }
    let report: [String: Any] = ["text": text.string, "dropCount": dropCount, "dropTypes": dropTypes,
                               "dropAccepted": dropAccepted, "attachments": attachments,
                               "x": screenPoint.x, "y": top - screenPoint.y,
                               "pid": ProcessInfo.processInfo.processIdentifier]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: output, options: .atomic)
    }
  }
}

@main
struct InputFixture {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    let delegate = FixtureDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
