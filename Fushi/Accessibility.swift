import AppKit
@preconcurrency import ApplicationServices

struct Accessibility {
  static var isAllowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  @discardableResult
  static func requestAuthorization() -> Bool {
    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
  }

  static func openSettings() {
    requestAuthorization()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  static func check() {
    guard !isAllowed else {
      return
    }
    requestAuthorization()
  }
}
