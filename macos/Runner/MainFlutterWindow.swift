import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    ForumVideoConverterPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumVideoConverterPlugin")
    )

    ForumPdfPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumPdfPlugin")
    )

    ForumCursorPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumCursorPlugin")
    )
    ForumCursorPlugin.attach(flutterView: flutterViewController.view)

    super.awakeFromNib()

    title = "Forum"
    makeKeyAndOrderFront(nil)
  }
}
