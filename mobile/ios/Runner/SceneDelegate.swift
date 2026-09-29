import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // iOS can't block screenshots, so the app is blurred whenever it leaves the
  // foreground: case text never shows in the app switcher.
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard privacyCover == nil, let window = window else { return }
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
