import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleApplicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func handleApplicationDidBecomeActive() {
    VeyaKeyboardCoordinator.shared.startPendingIfNeeded(from: window?.rootViewController)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VeyaPermissions") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.veya/permissions",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let session = AVAudioSession.sharedInstance()
      switch call.method {
      case "isMicrophoneGranted":
        result(session.recordPermission == .granted)
      case "requestMicrophone":
        switch session.recordPermission {
        case .granted:
          result(true)
        case .denied:
          result(false)
        case .undetermined:
          session.requestRecordPermission { granted in
            DispatchQueue.main.async { result(granted) }
          }
        @unknown default:
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "veya", url.host == "dictate" {
      VeyaKeyboardCoordinator.shared.start(from: window?.rootViewController)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
