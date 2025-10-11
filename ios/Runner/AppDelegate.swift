import UIKit
import Flutter
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "smart_display/deep_link"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Setup MethodChannel to communicate deep links to Flutter
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      DeepLinkManager.shared.configure(channel: channel)

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getInitialLink":
          result(DeepLinkManager.shared.consumePendingLink())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Capture possible universal link from cold start
    if let userActivityDictionary = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] {
        for (_, activity) in userActivityDictionary {
            if let userActivity = activity as? NSUserActivity,
                userActivity.activityType == NSUserActivityTypeBrowsingWeb,
                let url = userActivity.webpageURL {
            DeepLinkManager.shared.storePendingLink(url: url)
        }
    }
}

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle Universal Links while app is running or in background
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
      DeepLinkManager.shared.handle(url: url)
      return true
    }
    return false
  }

  // Handle custom URL schemes: smartdisplay://connect?...
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    DeepLinkManager.shared.handle(url: url)
    return true
  }
}
