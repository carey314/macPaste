import AppKit
import ApplicationServices
import Defaults

/// Retains only the target process/control handle, never the text in another app.
@MainActor
final class PoolPasteCoordinator {
  static let shared = PoolPasteCoordinator()

  private struct Target {
    let application: NSRunningApplication
    let input: AXUIElement
  }
  private var target: Target?
  private var operation: Task<Void, Never>?

  func captureTarget() {
    operation?.cancel()
    target = nil
    guard !PoolExperience.usesIsolatedData, Accessibility.isAllowed,
          let app = NSWorkspace.shared.frontmostApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
          let input = focusedInput(in: app) else { return }
    target = Target(application: app, input: input)
  }

  func activate(_ item: HistoryItemDecorator, copyOnly: Bool = false) {
    operation?.cancel()
    let target = target
    let revision = Clipboard.shared.copy(item.item, showNotification: false)
    AppState.shared.popup.close()
    guard let revision else {
      PoolFeedback.shared.show("剪贴板已更新 · 请重新选择")
      return
    }
    let decision = PoolPastePolicy.decision(
      enabled: Defaults[.poolAutoPaste], copyOnly: copyOnly, isolated: PoolExperience.usesIsolatedData,
      trusted: Accessibility.isAllowed, hasEditableTarget: target != nil)
    switch decision {
    case .copyOnly:
      PoolFeedback.shared.show("已复制")
    case .needsPermission:
      Accessibility.requestAuthorization()
      PoolFeedback.shared.show("已复制 · 自动粘贴需要辅助功能权限")
    case .noInput:
      PoolFeedback.shared.show("已复制 · 请先定位输入框再呼出浮拾")
    case .paste:
      guard let target else { return }
      operation = Task { [weak self] in
        // Let the non-activating pool release its field editor before returning input.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, let self, !target.application.isTerminated else { return }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if foreground == ProcessInfo.processInfo.processIdentifier {
          target.application.activate(options: [])
        }
        for _ in 0..<15 {
          if target.application.isActive { break }
          try? await Task.sleep(for: .milliseconds(20))
          if Task.isCancelled { return }
        }
        let input = self.focusedInput(in: target.application)
        let sameInput = input.map { CFEqual($0, target.input) } ?? false
        guard !Task.isCancelled, Defaults[.poolAutoPaste], PoolPastePolicy.canDeliver(
          trusted: Accessibility.isAllowed, targetActive: target.application.isActive,
          sameInput: sameInput, clipboardUnchanged: Clipboard.shared.currentChangeCount == revision
        ) else {
          PoolFeedback.shared.show("焦点或剪贴板已变化 · 未自动粘贴")
          return
        }
        // Address the event to this exact process, never whichever app happens to be foreground later.
        if Clipboard.shared.paste(to: target.application.processIdentifier) {
          PoolFeedback.shared.show("已粘贴")
        } else {
          PoolFeedback.shared.show("已复制 · 请检查辅助功能权限")
        }
      }
    }
  }

  private func focusedInput(in application: NSRunningApplication) -> AXUIElement? {
    let app = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.25)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    let input = unsafeBitCast(value, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(input, 0.25)
    var role: CFTypeRef?
    guard AXUIElementCopyAttributeValue(input, kAXRoleAttribute as CFString, &role) == .success,
          let role = role as? String, PoolPastePolicy.isTextInput(role: role) else { return nil }
    var valueWritable: DarwinBoolean = false
    var selectionWritable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(input, kAXValueAttribute as CFString, &valueWritable)
    AXUIElementIsAttributeSettable(input, kAXSelectedTextAttribute as CFString, &selectionWritable)
    guard PoolPastePolicy.isEditableTextInput(role: role, valueWritable: valueWritable.boolValue,
                                             selectedTextWritable: selectionWritable.boolValue) else { return nil }
    var enabled: CFTypeRef?
    if AXUIElementCopyAttributeValue(input, kAXEnabledAttribute as CFString, &enabled) == .success,
       let enabled = enabled as? Bool, !enabled { return nil }
    return input
  }
}
