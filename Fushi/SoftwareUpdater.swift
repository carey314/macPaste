import Sparkle

@Observable
class SoftwareUpdater {
  var automaticallyChecksForUpdates = false {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: !PoolExperience.isEnabled,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  init() {
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] _, change in
      guard change.newValue != change.oldValue, let newValue = change.newValue else {
        return
      }

      MainActor.assumeIsolated {
        self.automaticallyChecksForUpdates = newValue
      }
    }
  }

  func checkForUpdates() {
    guard !PoolExperience.isEnabled else { return }
    updater.checkForUpdates()
  }
}
