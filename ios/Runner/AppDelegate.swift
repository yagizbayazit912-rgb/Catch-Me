import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "catch_me/notify",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return result(FlutterMethodNotImplemented) }
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "update":
          let title = args?["title"] as? String ?? "Catch Me çalışıyor"
          let body = args?["body"] as? String ?? "Krallığın takip ediliyor."
          self.requestNotifications()
          self.post(title: title, body: body, identifier: "catch_me_ongoing", sound: false)
          result(true)
        case "alert":
          let title = args?["title"] as? String ?? "Catch Me"
          let body = args?["body"] as? String ?? ""
          self.requestNotifications()
          self.post(title: title, body: body, identifier: "catch_me_alert_\(Date().timeIntervalSince1970)", sound: true)
          result(true)
        case "hideTracking":
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["catch_me_ongoing"])
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["catch_me_ongoing"])
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func requestNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
  }

  func post(title: String, body: String, identifier: String, sound: Bool) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if sound { content.sound = .default }
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
