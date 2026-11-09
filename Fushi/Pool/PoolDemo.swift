import AppKit
import Defaults

/// Explicit opt-in demonstrations use an in-memory store and a named pasteboard.
@MainActor
enum PoolDemo {
  static var previewIsOpen = false
  static var currentPage = 0

  static func reportPermissionsIfRequested() {
    #if DEBUG
    guard PoolExperience.isEnabled, let index = CommandLine.arguments.firstIndex(of: "--pool-diagnostics"),
          CommandLine.arguments.indices.contains(index + 1) else { return }
    let path = CommandLine.arguments[index + 1]
    guard path.hasPrefix("/"), path.hasSuffix(".json") else { return }
    func writeReport() {
      var report: [String: Any] = ["accessibilityAllowed": Accessibility.isAllowed,
                                 "autoPaste": Defaults[.poolAutoPaste],
                                 "pid": ProcessInfo.processInfo.processIdentifier,
                                 "bundleIdentifier": Bundle.main.bundleIdentifier ?? ""]
      if PoolExperience.isDemo {
        report["dragInProgress"] = AppState.shared.navigator.isDragAndDropInProgress
        report["pinnedCount"] = History.shared.pinnedItems.count
        report["recentCount"] = History.shared.unpinnedItems.count
        report["pasteboardRevision"] = Clipboard.shared.currentChangeCount
        if let panel = AppState.shared.appDelegate?.panel {
          report["panelVisible"] = panel.isVisible
          report["panelPresented"] = panel.isPresented
        }
      }
      if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
      }
    }
    writeReport()
    if PoolExperience.isDemo {
      Task {
        for _ in 0..<1200 {
          try? await Task.sleep(for: .milliseconds(250))
          writeReport()
        }
      }
    }
    #endif
  }

  static func seed() {
    guard PoolExperience.isDemo else { return }
    Defaults[.openPreviewAutomatically] = false
    Defaults[.showSpecialSymbols] = false
    Defaults[.sortBy] = .lastCopiedAt
    Defaults[.size] = 200

    let samples: [(String, String, String)] = [
      ("下次见面，带上相机。", "com.apple.Notes", "text"),
      ("落日与海", "com.apple.Preview", "PoolSunset"),
      ("叶影与光", "com.apple.Preview", "PoolLeaves"),
      ("https://developer.apple.com/documentation/swiftui", "com.apple.Safari", "text"),
      ("npm run dev", "com.apple.Terminal", "text"),
      ("下周灵感", "com.apple.Notes", "text"),
      ("把灵感留给下一次创作", "com.apple.Notes", "text"),
      ("https://developer.apple.com/design/human-interface-guidelines", "com.apple.Safari", "text"),
      ("git status --short", "com.apple.Terminal", "text"),
      ("周末清单：相机、充电器、雨伞", "com.apple.Notes", "text"),
      ("空格放大预览，回车复制。", "com.apple.Notes", "text"),
      ("这是独立演示数据，不会出现在你的真实历史中。", "com.apple.Notes", "text")
    ]
    for (index, sample) in samples.enumerated().reversed() {
      let content: HistoryItemContent
      if sample.2 != "text", let data = imageData(named: sample.2) {
        content = HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: data)
      } else {
        content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: Data(sample.0.utf8))
      }
      let item = HistoryItem(contents: [content])
      item.title = sample.0.hasSuffix("documentation/swiftui") ? "SwiftUI 文档" : sample.0
      item.application = sample.1
      item.firstCopiedAt = Date().addingTimeInterval(Double(-index * 90))
      item.lastCopiedAt = item.firstCopiedAt
      History.shared.add(item)
    }
    let favorite = HistoryItem(contents: [HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: Data("慢一点，灵感会跟上。".utf8)
    )])
    favorite.title = "慢一点，灵感会跟上。"
    favorite.application = "com.apple.Notes"
    let decorated = History.shared.add(favorite)
    History.shared.togglePin(decorated)
  }

  private static func imageData(named name: String) -> Data? {
    guard let image = NSImage(named: name), let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  static func prepareVerification(panel: NSWindow?) {
    if PoolExperience.isDemo, CommandLine.arguments.contains("--pool-self-test"), let panel {
      Task { await PoolSelfVerification.run(in: panel) }
      return
    }
    guard PoolExperience.isDemo, let panel, let url = PoolExperience.snapshotURL else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      guard let view = panel.contentView else { return }
      view.layoutSubtreeIfNeeded()
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
      do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
      } catch {
        NSLog("Pool demo snapshot failed: %@", error.localizedDescription)
      }
    }
  }
}
