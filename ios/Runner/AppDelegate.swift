import Flutter
import UIKit

final class DeepLinkRelay: NSObject, FlutterStreamHandler {
  static let shared = DeepLinkRelay()

  private var eventSink: FlutterEventSink?
  private(set) var initialLink: String?

  func handle(url: URL) {
    let link = url.absoluteString
    initialLink = link
    eventSink?(link)
  }

  func clear() {
    initialLink = nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    DeepLinkRelay.shared.handle(url: url)
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: "msitlms/deep_links",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { call, result in
      if call.method == "getInitialLink" {
        result(DeepLinkRelay.shared.initialLink)
      } else if call.method == "getLatestLink" {
        result(DeepLinkRelay.shared.initialLink)
      } else if call.method == "clearLatestLink" {
        DeepLinkRelay.shared.clear()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "msitlms/deep_links/events",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(DeepLinkRelay.shared)
  }
}
