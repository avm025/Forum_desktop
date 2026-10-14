import Cocoa
import FlutterMacOS

/// Системный fullscreen окна (весь экран монитора).
class ForumWindowPlugin: NSObject, FlutterPlugin {
  private static weak var _instance: ForumWindowPlugin?
  private var enterWaiters: [FlutterResult] = []
  private var exitWaiters: [FlutterResult] = []
  private var observersInstalled = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/window",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumWindowPlugin()
    _instance = instance
    instance.installObserversIfNeeded()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isFullscreen":
      DispatchQueue.main.async {
        result(Self.isFullscreen)
      }
    case "enterFullscreen":
      DispatchQueue.main.async {
        self.enterFullscreen(result: result)
      }
    case "exitFullscreen":
      DispatchQueue.main.async {
        self.exitFullscreen(result: result)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installObserversIfNeeded() {
    guard !observersInstalled else { return }
    observersInstalled = true
    let nc = NotificationCenter.default
    nc.addObserver(
      self,
      selector: #selector(onDidEnterFullScreen(_:)),
      name: NSWindow.didEnterFullScreenNotification,
      object: nil
    )
    nc.addObserver(
      self,
      selector: #selector(onDidExitFullScreen(_:)),
      name: NSWindow.didExitFullScreenNotification,
      object: nil
    )
  }

  @objc private func onDidEnterFullScreen(_ note: Notification) {
    guard note.object as? NSWindow === Self.mainWindow else { return }
    flushWaiters(&enterWaiters, value: true)
  }

  @objc private func onDidExitFullScreen(_ note: Notification) {
    guard note.object as? NSWindow === Self.mainWindow else { return }
    flushWaiters(&exitWaiters, value: true)
  }

  private func flushWaiters(_ waiters: inout [FlutterResult], value: Bool) {
    let copy = waiters
    waiters.removeAll()
    for r in copy {
      r(value)
    }
  }

  private func enterFullscreen(result: @escaping FlutterResult) {
    guard let window = Self.mainWindow else {
      result(false)
      return
    }
    if window.styleMask.contains(.fullScreen) {
      result(true)
      return
    }
    enterWaiters.append(result)
    window.toggleFullScreen(nil)
    // На случай если нотификация не пришла.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self else { return }
      if !self.enterWaiters.isEmpty {
        self.flushWaiters(&self.enterWaiters, value: Self.isFullscreen)
      }
    }
  }

  private func exitFullscreen(result: @escaping FlutterResult) {
    guard let window = Self.mainWindow else {
      result(false)
      return
    }
    if !window.styleMask.contains(.fullScreen) {
      result(true)
      return
    }
    exitWaiters.append(result)
    window.toggleFullScreen(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self else { return }
      if !self.exitWaiters.isEmpty {
        self.flushWaiters(&self.exitWaiters, value: !Self.isFullscreen)
      }
    }
  }

  private static var mainWindow: NSWindow? {
    if let w = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      return w
    }
    return NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
  }

  private static var isFullscreen: Bool {
    guard let window = mainWindow else { return false }
    return window.styleMask.contains(.fullScreen)
  }
}
