import Flutter
import UIKit
import WebKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let cookieChannel = FlutterMethodChannel(name: "app.webview.cookies", binaryMessenger: controller.binaryMessenger)
    cookieChannel.setMethodCallHandler { call, result in
      if call.method == "getCookies" {
        guard let args = call.arguments as? [String: Any], let urlStr = args["url"] as? String,
              let url = URL(string: urlStr.hasPrefix("http") ? urlStr : "https://\(urlStr)") else {
          result("")
          return
        }
        // Combine from WKWebsiteDataStore and HTTPCookieStorage
        var headerParts: [String] = []
        let group = DispatchGroup()
        var added: Set<String> = []

        group.enter()
        if #available(iOS 11.0, *) {
          WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let host = url.host ?? ""
            for c in cookies {
              let domain = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
              let match = (host == domain) || (host.hasSuffix("." + domain))
              if match {
                let name = c.name
                if !added.contains(name) {
                  headerParts.append("\(name)=\(c.value)")
                  added.insert(name)
                }
              }
            }
            group.leave()
          }
        } else {
          group.leave()
        }

        group.enter()
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
          for c in cookies {
            let name = c.name
            if !added.contains(name) {
              headerParts.append("\(name)=\(c.value)")
              added.insert(name)
            }
          }
        }
        group.leave()

        group.notify(queue: .main) {
          result(headerParts.joined(separator: "; "))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Media channel
    let mediaChannel = FlutterMethodChannel(name: "app.media", binaryMessenger: controller.binaryMessenger)
    mediaChannel.setMethodCallHandler { call, result in
      if call.method == "saveImage" {
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              let image = UIImage(data: bytes.data) else {
          result(false)
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.creationRequestForAsset(from: image)
        }) { success, _ in
          result(success)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
