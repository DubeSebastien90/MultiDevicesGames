import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Phone-shaped, not the landscape desktop default.
    //
    // On desktop a "phone" is a window: the app measures whatever it is given
    // and reports that as a physical panel. A landscape window claims to be a
    // landscape phone, which the portrait-locked app does not believe — and the
    // board comes out turned a quarter turn from what the screen shows.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 460, height: 820)
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
