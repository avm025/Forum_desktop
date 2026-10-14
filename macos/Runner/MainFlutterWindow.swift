import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// UserDefaults key для позиции/размера главного окна.
  private static let frameAutosaveName = "ForumMainWindow"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

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

    ForumWindowPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumWindowPlugin")
    )

    ForumVideoPlayerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumVideoPlayerPlugin")
    )

    ForumMediaOverlayPlugin.register(
      with: flutterViewController.registrar(forPlugin: "ForumMediaOverlayPlugin")
    )

    super.awakeFromNib()

    title = "Forum"
    // До первого Flutter-кадра — не чёрный фон.
    backgroundColor = NSColor.windowBackgroundColor
    contentViewController?.view.wantsLayer = true
    contentViewController?.view.layer?.backgroundColor =
      NSColor.windowBackgroundColor.cgColor
    minSize = NSSize(width: 720, height: 480)
    isReleasedWhenClosed = false
    delegate = self

    // Восстановить позицию/размер; если впервые — оставить кадр из XIB и запомнить имя.
    setFrameAutosaveName(Self.frameAutosaveName)
    if !setFrameUsingName(Self.frameAutosaveName) {
      // Первый запуск: кадр из nib, центрируем на экране.
      center()
    }

    makeKeyAndOrderFront(nil)
  }

  /// Красная кнопка: скрыть в Dock (как Telegram), не выходить.
  /// Полный выход — Cmd+Q.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    saveFrame(usingName: Self.frameAutosaveName)
    orderOut(nil)
    (NSApp.delegate as? AppDelegate)?.onMainWindowHiddenForPush()
    return false
  }

  func windowDidResize(_ notification: Notification) {
    saveFrame(usingName: Self.frameAutosaveName)
  }

  func windowDidMove(_ notification: Notification) {
    saveFrame(usingName: Self.frameAutosaveName)
  }
}
