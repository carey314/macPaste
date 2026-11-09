import Foundation

/// Product boundaries are explicit so a locally signed build can never open Fushi's store.
nonisolated enum PoolExperience {
  static let bundleIdentifier = "dev.carey.shiguangpool"
  static var isEnabled: Bool { usesPool(bundleIdentifier: Bundle.main.bundleIdentifier) }
  static var isUnitTestHost: Bool {
    isEnabled && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }
  static var usesIsolatedData: Bool { isDemo || isUnitTestHost }
  static var isDemo: Bool {
    demoEnabled(bundleIdentifier: Bundle.main.bundleIdentifier, arguments: CommandLine.arguments)
  }

  static func usesPool(bundleIdentifier: String?) -> Bool {
    bundleIdentifier == self.bundleIdentifier
  }

  static func demoEnabled(bundleIdentifier: String?, arguments: [String]) -> Bool {
    usesPool(bundleIdentifier: bundleIdentifier) && arguments.contains("--pool-demo")
  }

  static func storageURL(base: URL, bundleIdentifier: String?) -> URL {
    base.appending(path: usesPool(bundleIdentifier: bundleIdentifier) ? "ShiguangPool" : "Maccy")
      .appending(path: "Storage.sqlite")
  }

  static func panelSize(available: CGSize) -> CGSize {
    CGSize(width: min(1160, max(1, available.width - 48)),
           height: min(730, max(1, available.height - 48)))
  }

  static var snapshotURL: URL? {
    guard isDemo, let index = CommandLine.arguments.firstIndex(of: "--pool-snapshot"),
          CommandLine.arguments.indices.contains(index + 1) else { return nil }
    let path = CommandLine.arguments[index + 1]
    guard path.hasPrefix("/"), path.hasSuffix(".png") else { return nil }
    return URL(fileURLWithPath: path)
  }
}
