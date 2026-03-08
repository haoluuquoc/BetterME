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
    
    // MethodChannel cho iOS native methods
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.betterme.betterme/app", binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "moveToBackground":
        // iOS không có moveToBackground trực tiếp, suspend app bằng cách về Home
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        result(nil)
      case "closeApp":
        // iOS không cho phép đóng app theo chính sách Apple, chỉ suspend
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        result(nil)
      case "canDrawOverlays":
        // iOS không có overlay permission
        result(true)
      case "openOverlaySettings":
        result(nil)
      case "isBatteryOptimized":
        // iOS không có battery optimization setting
        result(false)
      case "openBatterySettings":
        result(nil)
      case "getDeviceManufacturer":
        result("apple")
      case "openAutoStartSettings":
        // iOS không cần auto-start
        result(false)
      case "installApk":
        // iOS không dùng APK
        result(false)
      case "requestActivityRecognition":
        // iOS dùng NSMotionUsageDescription, không cần runtime request
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
