import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    guard let url = URLContexts.first?.url, url.scheme == "veya", url.host == "dictate" else {
      return
    }
    VeyaKeyboardCoordinator.shared.start(from: window?.rootViewController)
  }
}
