import AppKit
import UserNotifications

class Notifier {
  nonisolated private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

  static func preparePoolFeedback() {
    guard PoolExperience.isEnabled, !PoolExperience.usesIsolatedData,
          UserDefaults.standard.integer(forKey: "poolFeedbackVersion") < 1 else { return }
    center.removeAllDeliveredNotifications()
    UserDefaults.standard.set(1, forKey: "poolFeedbackVersion")
  }

  static func authorize() {
    center.requestAuthorization(options: [.alert, .sound]) { _, error in
      if error != nil {
        NSLog("Failed to authorize notifications: \(String(describing: error))")
      }
    }
  }

  static func notify(body: String?, sound: NSSound?) {
    guard let body else { return }

    if PoolExperience.isEnabled {
      PoolFeedback.shared.show("已复制")
      return
    }

    authorize()

    center.getNotificationSettings { settings in
      guard (settings.authorizationStatus == .authorized) ||
            (settings.authorizationStatus == .provisional) else { return }

      let isAlertEnabled = settings.alertSetting == .enabled
      let isSoundEnabled = settings.soundSetting == .enabled

      let content = UNMutableNotificationContent()
      if isAlertEnabled {
        content.body = body
      }

      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request) { error in
        if error != nil {
          NSLog("Failed to deliver notification: \(String(describing: error))")
        } else {
          if isSoundEnabled {
            sound?.play()
          }
        }
      }
    }
  }
}
