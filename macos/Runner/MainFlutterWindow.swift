import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The app is dark whatever the system theme is, so its frame is too, and
    // the title bar takes the colour of the backdrop beneath it.
    self.appearance = NSAppearance(named: .darkAqua)
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(
      srgbRed: 0x04 / 255.0, green: 0x05 / 255.0, blue: 0x0d / 255.0, alpha: 1)
    self.title = "Port Why"

    self.setContentSize(NSSize(width: 1280, height: 800))
    // Down to a single column of cards.
    self.contentMinSize = NSSize(width: 440, height: 420)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
