import AppKit
import Defaults

/// A local demo-only input harness. It posts events into this application, never into other apps.
@MainActor
enum PoolSelfVerification {
  private struct Check: Codable { let name: String; let passed: Bool }
  private struct Report: Codable {
    let scope: String
    let accessibilityAllowed: Bool
    let passed: Bool
    let checks: [Check]
    let limitations: [String]
  }

  static func run(in panel: NSWindow) async {
    guard PoolExperience.isDemo, let imageURL = PoolExperience.snapshotURL else { return }
    var checks: [Check] = []
    func check(_ name: String, _ passed: Bool) { checks.append(Check(name: name, passed: passed)) }
    let history = History.shared
    let board = NSPasteboard(name: .init("dev.carey.shiguangpool.demo"))
    await settle()
    // Launch Services may send its reopen event after the initial panel presentation.
    // Establish a real key-window precondition before posting local demo events.
    NSApp.activate()
    AppState.shared.appDelegate?.panel.open(height: Defaults[.windowSize].height, at: .center)
    for _ in 0..<15 {
      if panel.isVisible && panel.isKeyWindow { break }
      try? await Task.sleep(for: .milliseconds(200))
    }
    await settle()
    check("Synthetic memory dataset loaded", history.unpinnedItems.count == 12 && history.pinnedItems.count == 1)
    check("Own panel is presented", panel.isVisible)
    check("Own panel is key before native event checks", panel.isKeyWindow)
    capture(panel, to: imageURL)

    let wasAutoPaste = Defaults[.poolAutoPaste]
    AppState.shared.openPreferences()
    await settle()
    if let settings = NSApp.keyWindow, settings.title == "浮拾设置" {
      Defaults[.poolAutoPaste] = false
      await settle()
      check("Auto-paste setting can be disabled independently", !Defaults[.poolAutoPaste])
      capture(settings, to: imageURL.deletingLastPathComponent().appending(path: "浮拾-设置-仅复制.png"))
      Defaults[.poolAutoPaste] = true
      await settle()
      check("Auto-paste setting can be enabled", Defaults[.poolAutoPaste])
      capture(settings, to: imageURL.deletingLastPathComponent().appending(path: "浮拾-设置-自动粘贴.png"))
      settings.close()
    } else { check("Native preferences window presents auto-paste switch", false) }
    Defaults[.poolAutoPaste] = wasAutoPaste
    PoolFeedback.shared.show("已复制")
    await settle()
    PoolFeedback.shared.captureDemo(to: imageURL.deletingLastPathComponent().appending(path: "浮拾-新图标轻提示.png"))
    AppState.shared.appDelegate?.panel.open(height: Defaults[.windowSize].height, at: .center)
    await settle()
    capture(panel, to: imageURL)

    let originalCount = history.items.count
    if let item = history.firstUnpinnedItem {
      let revision = Clipboard.shared.copy(item.item, showNotification: false)
      check("Copy returns the named pasteboard ownership revision", revision != nil && revision == board.changeCount)
      board.clearContents()
      board.setString("synthetic competing copy", forType: .string)
      check("An intervening copy invalidates the old ownership token", revision != board.changeCount)
    }
    if let editor = panel.firstResponder as? NSTextView {
      check("Native search editor has focus", editor.isFieldEditor)
      editor.selectAll(nil)
      editor.insertText("npm", replacementRange: NSRange(location: NSNotFound, length: 0))
      await settle()
      check("Native search field filters records", history.searchQuery == "npm" && history.unpinnedItems.count == 1)
      postKey(51, "\u{7f}", modifiers: .command, panel: panel)
      await waitUntil { history.searchQuery.isEmpty && history.items.count == originalCount }
      check("Command-delete edits search without deleting history", history.searchQuery.isEmpty && history.items.count == originalCount)
    } else {
      check("Native search editor has focus", false)
    }

    postKey(121, "\u{f72d}", panel: panel)
    await settle()
    check("Native PageDown event changes pool page", PoolDemo.currentPage == 1)
    postKey(116, "\u{f72c}", panel: panel)
    await settle()
    check("Native PageUp event returns to first page", PoolDemo.currentPage == 0)

    postKey(49, " ", panel: panel)
    await settle()
    check("Native space event opens preview", PoolDemo.previewIsOpen)
    capture(panel, to: imageURL.deletingLastPathComponent().appending(path: "浮拾-原生预览.png"))
    postKey(53, "\u{1b}", panel: panel)
    await settle()
    check("Escape closes preview but keeps pool open", !PoolDemo.previewIsOpen && panel.isVisible)

    if let first = history.firstUnpinnedItem {
      let count = history.pinnedItems.count
      history.togglePin(first)
      await settle()
      check("Favorite pin persists in the real history model", first.isPinned && history.pinnedItems.count == count + 1)
      history.togglePin(first)
      await settle()
      check("Favorite unpin restores recent content", first.isUnpinned && history.pinnedItems.count == count)
      AppState.shared.navigator.selectWithoutScrolling(item: history.firstUnpinnedItem)
    }

    if let image = history.unpinnedItems.first(where: { $0.hasImage }) {
      let provider = PoolDrag.provider(for: image)
      let exported = await representation(provider, type: NSPasteboard.PasteboardType.png.rawValue)
      check("Image drag exports original PNG bytes", exported == image.item.imageData && exported != nil)
      let native = PoolDrag.pasteboardItems(for: image).first
      check("Native image drag preserves original PNG", native?.data(forType: .png) == image.item.imageData)
      check("Native image drag includes immediate TIFF for Cocoa editors", native?.data(forType: .tiff) != nil)
    } else { check("Image drag exports original PNG bytes", false) }
    if let text = history.unpinnedItems.first(where: { $0.item.text == "npm run dev" }) {
      let provider = PoolDrag.provider(for: text)
      let exported = await representation(provider, type: NSPasteboard.PasteboardType.string.rawValue)
      check("Text drag exports complete original text", exported == Data("npm run dev".utf8))
    } else { check("Text drag exports complete original text", false) }

    history.searchQuery = "no-such-clip-987654"
    await settle()
    check("No-results search has no accidental selection", history.unpinnedItems.isEmpty && history.pinnedItems.isEmpty)
    capture(panel, to: imageURL.deletingLastPathComponent().appending(path: "浮拾-无搜索结果.png"))
    history.searchQuery = ""
    await settle()

    let dark = NSAppearance(named: .darkAqua)
    panel.appearance = dark
    await settle()
    capture(panel, to: imageURL.deletingLastPathComponent().appending(path: "浮拾-深色.png"))
    check("Dark appearance renders", panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    panel.appearance = NSAppearance(named: .aqua)
    await settle()

    AppState.shared.navigator.selectWithoutScrolling(item: history.firstUnpinnedItem)
    let expected = history.firstUnpinnedItem?.item.text
    postKey(36, "\r", panel: panel)
    await settle()
    check("Native Return event copies to the isolated demo pasteboard", expected != nil && board.string(forType: .string) == expected)
    check("Copy action closes own pool panel", !panel.isVisible)
    AppState.shared.appDelegate?.panel.open(height: Defaults[.windowSize].height, at: .center)
    await settle()
    capture(panel, to: imageURL)

    let report = Report(
      scope: "In-process native demo events and real model/payload integration; no global clipboard or security changes",
      accessibilityAllowed: Accessibility.isAllowed,
      passed: checks.allSatisfy(\.passed), checks: checks,
      limitations: ["Xcode UI runner was blocked by macOS and no UI automation pass is claimed.",
                    "Cross-application physical dragging and macOS14/15 compatibility require separate device checks."]
    )
    do {
      let data = try JSONEncoder().encode(report)
      try data.write(to: imageURL.deletingLastPathComponent().appending(path: "浮拾-应用内自检.json"), options: .atomic)
    } catch { NSLog("Pool verification report failed: %@", error.localizedDescription) }
  }

  private static func settle() async { try? await Task.sleep(for: .milliseconds(450)) }

  private static func waitUntil(_ predicate: @MainActor () -> Bool) async {
    for _ in 0..<40 {
      if predicate() { return }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  private static func postKey(_ code: UInt16, _ characters: String,
                              modifiers: NSEvent.ModifierFlags = [], panel: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
      if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: panel.windowNumber, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: code) {
        NSApp.postEvent(event, atStart: false)
      }
    }
  }

  private static func representation(_ provider: NSItemProvider, type: String) async -> Data? {
    await withCheckedContinuation { continuation in
      provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
    }
  }

  private static func capture(_ panel: NSWindow, to url: URL) {
    guard let view = panel.contentView else { return }
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    do { try png.write(to: url, options: .atomic) }
    catch { NSLog("Pool verification snapshot failed: %@", error.localizedDescription) }
  }
}
