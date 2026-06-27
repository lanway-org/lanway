import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Don't destroy the window when it's closed, so closing (✕) just hides it
    // and it can be re-shown from the menu-bar app or the Dock icon.
    self.isReleasedWhenClosed = false

    super.awakeFromNib()
  }
}
