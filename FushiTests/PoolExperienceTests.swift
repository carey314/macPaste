import Foundation
import Testing
@testable import Fushi

struct PoolExperienceTests {
  @Test("The official app cannot opt into fork storage or demo mode")
  func officialIdentityStaysOfficial() {
    let base = URL(fileURLWithPath: "/tmp/pool-policy", isDirectory: true)
    #expect(!PoolExperience.usesPool(bundleIdentifier: "org.p0deje.Maccy"))
    #expect(!PoolExperience.demoEnabled(bundleIdentifier: "org.p0deje.Maccy", arguments: ["--pool-demo"]))
    #expect(PoolExperience.storageURL(base: base, bundleIdentifier: "org.p0deje.Maccy").path == "/tmp/pool-policy/Maccy/Storage.sqlite")
  }

  @Test("Fork storage is distinct even when sandboxing is absent")
  func forkStorageNeverUsesFushi() {
    let base = URL(fileURLWithPath: "/tmp/pool-policy", isDirectory: true)
    let fork = PoolExperience.storageURL(base: base, bundleIdentifier: "dev.carey.shiguangpool")
    #expect(fork.path == "/tmp/pool-policy/ShiguangPool/Storage.sqlite")
    #expect(fork != PoolExperience.storageURL(base: base, bundleIdentifier: "org.p0deje.Maccy"))
    #expect(!PoolExperience.usesPool(bundleIdentifier: nil))
  }

  @Test("Demo requires both explicit fork identity and explicit launch argument")
  func demoIsOptIn() {
    #expect(PoolExperience.demoEnabled(bundleIdentifier: "dev.carey.shiguangpool", arguments: ["--pool-demo"]))
    #expect(!PoolExperience.demoEnabled(bundleIdentifier: "dev.carey.shiguangpool", arguments: []))
    #expect(!PoolExperience.demoEnabled(bundleIdentifier: nil, arguments: ["--pool-demo"]))
  }

  @Test("Panel fits the available screen, including small displays", arguments: [
    CGSize(width: 1440, height: 900), CGSize(width: 1024, height: 720), CGSize(width: 640, height: 480)
  ])
  func panelFits(available: CGSize) {
    let size = PoolExperience.panelSize(available: available)
    #expect(size.width > 0 && size.height > 0)
    #expect(size.width <= available.width - 32)
    #expect(size.height <= available.height - 32)
  }
}
