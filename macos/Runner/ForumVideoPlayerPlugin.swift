import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS

/// Отдельное окно только с видео на весь экран (основное окно приложения не трогаем).
class ForumVideoPlayerPlugin: NSObject, FlutterPlugin, NSWindowDelegate {
  private var playerWindow: NSWindow?
  private var playerView: AVPlayerView?
  private var player: AVPlayer?
  private var pendingResult: FlutterResult?
  private var statusObserver: NSKeyValueObservation?
  private var completed = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/video_player",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumVideoPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "playFullscreen":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "map required", details: nil))
        return
      }
      DispatchQueue.main.async {
        self.playFullscreen(args: args, result: result)
      }
    case "close":
      DispatchQueue.main.async {
        self.closePlayer(success: true)
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func playFullscreen(args: [String: Any], result: @escaping FlutterResult) {
    closePlayer(success: true)

    let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let headers = args["headers"] as? [String: String]

    let asset: AVURLAsset?
    if let path, !path.isEmpty {
      let fileURL = URL(fileURLWithPath: path)
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "NO_FILE", message: "file missing", details: path))
        return
      }
      asset = AVURLAsset(url: fileURL)
    } else if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
      var options: [String: Any] = [:]
      if let headers, !headers.isEmpty {
        options["AVURLAssetHTTPHeaderFieldsKey"] = headers
      }
      asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
    } else {
      result(FlutterError(code: "INVALID_ARGS", message: "path or url required", details: nil))
      return
    }

    guard let asset else {
      result(FlutterError(code: "INVALID_URL", message: "cannot open", details: nil))
      return
    }

    completed = false
    pendingResult = result

    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    self.player = player

    statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard let self else { return }
      if item.status == .failed {
        DispatchQueue.main.async {
          let msg = item.error?.localizedDescription ?? "playback failed"
          self.failAndClose(message: msg)
        }
      }
    }

    let playerView = AVPlayerView()
    playerView.controlsStyle = .floating
    playerView.showsFullScreenToggleButton = false
    playerView.player = player
    self.playerView = playerView

    let screen = NSScreen.main ?? NSScreen.screens.first
    let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)

    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Video"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .black
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
    window.contentView = playerView
    window.delegate = self
    window.center()
    self.playerWindow = window

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    // Только это окно — в системный fullscreen; чат остаётся в обычном окне.
    if window.styleMask.contains(.fullScreen) == false {
      window.toggleFullScreen(nil)
    }
    player.play()
  }

  private func failAndClose(message: String) {
    let callback = pendingResult
    pendingResult = nil
    tearDown()
    callback?(FlutterError(code: "PLAY_FAILED", message: message, details: nil))
  }

  private func closePlayer(success: Bool) {
    guard !completed else {
      tearDown()
      return
    }
    completed = true
    let callback = pendingResult
    pendingResult = nil
    tearDown()
    if success {
      callback?(nil)
    }
  }

  private func tearDown() {
    statusObserver?.invalidate()
    statusObserver = nil
    player?.pause()
    playerView?.player = nil
    if let window = playerWindow {
      window.delegate = nil
      window.orderOut(nil)
      window.close()
    }
    playerWindow = nil
    playerView = nil
    player = nil
  }

  func windowWillClose(_ notification: Notification) {
    closePlayer(success: true)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    // Esc / выход из Space — закрываем только видео-окно.
    closePlayer(success: true)
  }
}
