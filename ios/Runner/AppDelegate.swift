import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Đăng ký notification delegate để nhận notification khi app ở foreground
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    // Gọi super TRƯỚC để Flutter tạo window + engine
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // MethodChannel cho iOS native methods (sau khi window đã sẵn sàng)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.betterme.betterme/app", binaryMessenger: controller.binaryMessenger)
      
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        switch call.method {
        case "moveToBackground":
          UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
          result(nil)
        case "closeApp":
          UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
          result(nil)
        case "canDrawOverlays":
          result(true)
        case "openOverlaySettings":
          result(nil)
        case "isBatteryOptimized":
          result(false)
        case "openBatterySettings":
          result(nil)
        case "getDeviceManufacturer":
          result("apple")
        case "openAutoStartSettings":
          result(false)
        case "installApk":
          result(false)
        case "requestActivityRecognition":
          result(true)
        case "openAppSettings":
          // Mở Settings > BetterMe để user có thể cấp quyền Health
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    return result
  }
  
  // Cho phép notification hiện khi app đang ở foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }
}
