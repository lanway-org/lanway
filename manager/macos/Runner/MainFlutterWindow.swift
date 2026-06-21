import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Don't let macOS restore a previously-saved (smaller) frame over ours.
    self.isRestorable = false

    // Open at ~80% of the screen, centered.
    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let width = visible.width * 0.8
      let height = visible.height * 0.8
      let x = visible.origin.x + (visible.width - width) / 2
      let y = visible.origin.y + (visible.height - height) / 2
      self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
