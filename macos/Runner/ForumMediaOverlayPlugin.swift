import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS
import PDFKit

/// Отдельное окно на весь монитор с blur. Окно приложения не меняется.
class ForumMediaOverlayPlugin: NSObject, FlutterPlugin, NSWindowDelegate {
  private var channel: FlutterMethodChannel?
  private var overlayWindow: NSWindow?
  private var player: AVPlayer?
  private weak var playerView: AVPlayerView?
  private var statusObserver: NSKeyValueObservation?
  private var keyMonitor: Any?
  private var pendingResult: FlutterResult?
  private var completed = false

  private weak var rootView: OverlayRootView?
  private weak var mediaContainer: NSView?
  private weak var metaView: NSView?
  private weak var chatLabel: NSTextField?
  private weak var dateLabel: NSTextField?
  private weak var toolbarView: NSStackView?

  private var mediaKind = ""
  private var dockClearance: CGFloat = 96
  private var zoomScale: CGFloat = 1.0
  private var baseMediaFrame: NSRect = .zero
  private var savedMainWindowLevel: NSWindow.Level?
  private var savedMainFrame: NSRect?
  private var savedMainStyle: NSWindow.StyleMask?
  private var savedMainOpaque: Bool?
  private var savedMainBackground: NSColor?
  private var savedMainAlpha: CGFloat = 1
  private var appUiRaised = false
  private var appUiClickMonitor: Any?
  private var appUiClickArmedAt: Date?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/media_overlay",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumMediaOverlayPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGS", message: "map required", details: nil))
        return
      }
      DispatchQueue.main.async {
        self.show(args: args, result: result)
      }
    case "close":
      DispatchQueue.main.async {
        self.close(success: true)
        result(nil)
      }
    case "prepareForAppUi":
      DispatchQueue.main.async {
        self.raiseAppUiAboveOverlay(visible: false)
        result(nil)
      }
    case "revealAppUi":
      DispatchQueue.main.async {
        self.revealAppUi()
        result(nil)
      }
    case "restoreOverlay":
      DispatchQueue.main.async {
        self.restoreOverlayAboveApp()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(args: [String: Any], result: @escaping FlutterResult) {
    close(success: true)

    let kind = ((args["kind"] as? String) ?? "").lowercased()
    mediaKind = kind
    let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let headers = args["headers"] as? [String: String]
    let text = args["text"] as? String
    let chatTitle = ((args["chatTitle"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let dateText = ((args["dateLabel"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    zoomScale = 1.0

    guard let screen = Self.targetScreen else {
      result(FlutterError(code: "NO_SCREEN", message: "no screen", details: nil))
      return
    }

    completed = false
    pendingResult = result
    dockClearance = Self.dockClearance(for: screen)

    let frame = screen.frame
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.level = .modalPanel
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    window.setFrame(frame, display: true)
    window.delegate = self
    overlayWindow = window

    let root = OverlayRootView(frame: NSRect(origin: .zero, size: frame.size))
    root.wantsLayer = true
    root.isAppUiRaised = { [weak self] in self?.appUiRaised == true }
    root.onBackdropClick = { [weak self] in
      guard let self else { return }
      // Пока открыта пересылка — клик мимо / по видео закрывает только её.
      if self.appUiRaised {
        NSLog("[ForumOverlay] backdrop → dismissAppUi")
        self.channel?.invokeMethod("dismissAppUi", arguments: nil)
      } else {
        self.close(success: true)
      }
    }
    root.onMediaHoverChanged = { [weak self] hovering in
      guard let pv = self?.playerView else { return }
      // Контролы только при наведении — без постоянной чёрной полосы.
      pv.controlsStyle = hovering ? .inline : .none
    }
    rootView = root

    let effect = NSVisualEffectView(frame: root.bounds)
    effect.autoresizingMask = [.width, .height]
    effect.material = .hudWindow
    effect.blendingMode = .behindWindow
    effect.state = .active
    root.addSubview(effect)

    let dim = NSView(frame: root.bounds)
    dim.autoresizingMask = [.width, .height]
    dim.wantsLayer = true
    dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    root.addSubview(dim)

    let container = NSView(frame: .zero)
    container.wantsLayer = true
    mediaContainer = container
    root.mediaView = container
    root.addSubview(container)

    // Мета слева над Dock.
    let meta = NSView(frame: .zero)
    metaView = meta
    root.addSubview(meta)

    let chatField = Self.makeLabel()
    chatField.textColor = .white
    chatField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    chatField.stringValue = chatTitle
    chatField.isHidden = chatTitle.isEmpty
    chatLabel = chatField
    meta.addSubview(chatField)

    let dateField = Self.makeLabel()
    dateField.textColor = NSColor.white.withAlphaComponent(0.75)
    dateField.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    dateField.stringValue = dateText
    dateField.isHidden = dateText.isEmpty
    dateLabel = dateField
    meta.addSubview(dateField)

    // Тулбар справа: −zoom / +zoom / forward — кнопки по центру пузыря
    let toolbar = NSStackView()
    toolbar.orientation = .horizontal
    toolbar.alignment = .centerY
    toolbar.spacing = 16
    toolbar.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
    toolbar.wantsLayer = true
    toolbar.layer?.backgroundColor =
      NSColor(calibratedWhite: 0.12, alpha: 0.72).cgColor
    toolbar.layer?.cornerRadius = 18
    toolbarView = toolbar
    root.addSubview(toolbar)

    for btn in [
      iconButton("minus.magnifyingglass", #selector(onZoomOut), "Уменьшить"),
      iconButton("plus.magnifyingglass", #selector(onZoomIn), "Увеличить"),
      iconButton("arrowshape.turn.up.right", #selector(onForward), "Переслать"),
    ] {
      btn.setContentHuggingPriority(.required, for: .horizontal)
      btn.setContentHuggingPriority(.required, for: .vertical)
      btn.setContentCompressionResistancePriority(.required, for: .horizontal)
      btn.setContentCompressionResistancePriority(.required, for: .vertical)
      toolbar.addArrangedSubview(btn)
    }

    window.contentView = root
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    installKeyMonitor()

    let maxW = availableMediaMaxWidth(in: root)
    let maxH = availableMediaMaxHeight(in: root)
    switch kind {
    case "image":
      presentImage(path: path, urlString: urlString, headers: headers, maxW: maxW, maxH: maxH, in: container, root: root)
    case "video":
      presentVideo(path: path, urlString: urlString, headers: headers, maxW: maxW, maxH: maxH, in: container, root: root)
    case "pdf":
      presentPdf(path: path, maxW: maxW, maxH: maxH, in: container, root: root)
    case "text":
      presentText(text: text, path: path, maxW: min(maxW, 900), maxH: maxH, in: container, root: root)
    default:
      fail(message: "unsupported kind \(kind)")
      return
    }
    layoutChrome()
  }

  private func availableMediaMaxHeight(in root: NSView) -> CGFloat {
    // Место снизу: Dock + тулбар/мета + пузырь (при hover).
    let bottomReserve = dockClearance + 100 + 24
    let topPad: CGFloat = 40
    return max(220, root.bounds.height - bottomReserve - topPad)
  }

  private func availableMediaMaxWidth(in root: NSView) -> CGFloat {
    // Почти на весь экран — без широких тёмных полей по бокам.
    max(320, root.bounds.width - 48)
  }

  private func iconButton(_ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
    let size: CGFloat = 68
    let btn = NSButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
    btn.bezelStyle = .regularSquare
    btn.isBordered = false
    let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
    btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
      .withSymbolConfiguration(config)
    btn.contentTintColor = .white
    btn.imageScaling = .scaleProportionallyDown
    btn.target = self
    btn.action = action
    btn.toolTip = tip
    btn.setFrameSize(NSSize(width: size, height: size))
    return btn
  }

  private static func makeLabel() -> NSTextField {
    let f = NSTextField(labelWithString: "")
    f.isBezeled = false
    f.drawsBackground = false
    f.isEditable = false
    f.isSelectable = false
    f.lineBreakMode = .byTruncatingTail
    return f
  }

  private static func dockClearance(for screen: NSScreen) -> CGFloat {
    let dockH = max(0, screen.visibleFrame.minY - screen.frame.minY)
    return max(88, dockH + 28)
  }

  // MARK: - Actions

  @objc private func onZoomIn() {
    zoomScale = min(3.0, zoomScale + 0.25)
    applyZoom()
  }

  @objc private func onZoomOut() {
    zoomScale = max(0.5, zoomScale - 0.25)
    applyZoom()
  }

  @objc private func onForward() {
    NSLog("[ForumOverlay] onForward")
    channel?.invokeMethod("action", arguments: ["action": "forward"])
  }

  /// Компактное окно диалога поверх медиа. visible=false — без мигания чата.
  private func raiseAppUiAboveOverlay(visible: Bool) {
    guard let overlay = overlayWindow,
          let main = Self.mainAppWindow,
          let screen = overlay.screen ?? NSScreen.main
    else { return }

    if !appUiRaised {
      savedMainWindowLevel = main.level
      savedMainFrame = main.frame
      savedMainStyle = main.styleMask
      savedMainOpaque = main.isOpaque
      savedMainBackground = main.backgroundColor
      savedMainAlpha = main.alphaValue
    }

    let vf = screen.visibleFrame
    let w: CGFloat = 520
    let h: CGFloat = min(760, vf.height * 0.88)
    let frame = NSRect(
      x: vf.midX - w / 2,
      y: vf.midY - h / 2,
      width: w,
      height: h
    )

    main.styleMask = [.titled, .closable, .fullSizeContentView]
    main.titleVisibility = .hidden
    main.titlebarAppearsTransparent = true
    main.isOpaque = true
    main.backgroundColor = savedMainBackground ?? main.backgroundColor
    main.hasShadow = true
    main.alphaValue = visible ? 1 : 0
    main.setFrame(frame, display: true)
    overlay.level = .modalPanel
    main.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.modalPanelWindow)) + 2)
    main.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    appUiRaised = true
    NSLog("[ForumOverlay] raiseAppUi visible=%d", visible)
    keepMediaPlaying()
  }

  private func revealAppUi() {
    guard let main = Self.mainAppWindow, appUiRaised else { return }
    main.alphaValue = 1
    main.makeKeyAndOrderFront(nil)
    NSLog("[ForumOverlay] revealAppUi")
    keepMediaPlaying()
    // Монитор после показа: клик по видео/оверлею закрывает пересылку.
    // Задержка — не поймать тот же клик, что открыл окно.
    installAppUiClickMonitor(armAfter: 0.35)
  }

  private func keepMediaPlaying() {
    guard let player else { return }
    if player.rate == 0 {
      player.play()
    }
  }

  /// Клик вне окна пересылки (в т.ч. по видео) → dismissAppUi.
  private func installAppUiClickMonitor(armAfter: TimeInterval) {
    removeAppUiClickMonitor()
    appUiClickArmedAt = Date().addingTimeInterval(armAfter)
    appUiClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
      guard let self, self.appUiRaised, let main = Self.mainAppWindow else { return event }
      if let armed = self.appUiClickArmedAt, Date() < armed { return event }
      // Клик в окне пересылки — не трогаем.
      if event.window === main { return event }
      NSLog("[ForumOverlay] outside click → dismissAppUi")
      self.channel?.invokeMethod("dismissAppUi", arguments: nil)
      return event
    }
  }

  private func removeAppUiClickMonitor() {
    if let appUiClickMonitor {
      NSEvent.removeMonitor(appUiClickMonitor)
      self.appUiClickMonitor = nil
    }
    appUiClickArmedAt = nil
  }

  private func restoreOverlayAboveApp() {
    NSLog("[ForumOverlay] restoreOverlay")
    removeAppUiClickMonitor()
    let main = Self.mainAppWindow
    if let main {
      if let style = savedMainStyle {
        main.styleMask = style
      }
      if let frame = savedMainFrame {
        main.setFrame(frame, display: true)
      }
      if let opaque = savedMainOpaque {
        main.isOpaque = opaque
      }
      if let bg = savedMainBackground {
        main.backgroundColor = bg
      }
      if let saved = savedMainWindowLevel {
        main.level = saved
      } else {
        main.level = .normal
      }
      main.alphaValue = savedMainAlpha > 0 ? savedMainAlpha : 1
      main.titleVisibility = .visible
      main.titlebarAppearsTransparent = false
      main.hasShadow = true
    }
    savedMainWindowLevel = nil
    savedMainFrame = nil
    savedMainStyle = nil
    savedMainOpaque = nil
    savedMainBackground = nil
    overlayWindow?.level = .modalPanel
    overlayWindow?.orderFront(nil)
    appUiRaised = false
    keepMediaPlaying()
  }

  private static var mainAppWindow: NSWindow? {
    if let w = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      return w
    }
    return NSApp.mainWindow
  }

  private func applyZoom() {
    guard let container = mediaContainer, baseMediaFrame.width > 1 else { return }
    let cx = baseMediaFrame.midX
    let cy = baseMediaFrame.midY
    let w = baseMediaFrame.width * zoomScale
    let h = baseMediaFrame.height * zoomScale
    container.frame = NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    for sub in container.subviews {
      sub.frame = container.bounds
    }
  }

  private func layoutChrome() {
    guard let root = rootView else { return }
    let pad: CGFloat = 28
    let metaBottom = dockClearance

    if let meta = metaView {
      let chatH: CGFloat = (chatLabel?.isHidden == false) ? 20 : 0
      let dateH: CGFloat = (dateLabel?.isHidden == false) ? 18 : 0
      let gap: CGFloat = (chatH > 0 && dateH > 0) ? 3 : 0
      let metaH = chatH + dateH + gap
      meta.frame = NSRect(x: pad, y: metaBottom, width: 440, height: max(metaH, 1))
      var y: CGFloat = 0
      if let date = dateLabel, !date.isHidden {
        date.frame = NSRect(x: 0, y: y, width: 440, height: dateH)
        y += dateH + gap
      }
      if let chat = chatLabel, !chat.isHidden {
        chat.frame = NSRect(x: 0, y: y, width: 440, height: chatH)
      }
    }

    if let toolbar = toolbarView {
      toolbar.layoutSubtreeIfNeeded()
      let size = toolbar.fittingSize
      let w = ceil(size.width)
      let h = ceil(size.height)
      toolbar.frame = NSRect(
        x: root.bounds.width - pad - w,
        y: metaBottom,
        width: w,
        height: h
      )
    }
  }

  // MARK: - Presenters

  private func presentImage(
    path: String?,
    urlString: String?,
    headers: [String: String]?,
    maxW: CGFloat,
    maxH: CGFloat,
    in container: NSView,
    root: NSView
  ) {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 8
    imageView.layer?.masksToBounds = true
    container.addSubview(imageView)

    if let path, !path.isEmpty, let img = NSImage(contentsOfFile: path) {
      layoutMedia(container, in: root, mediaSize: img.size, maxW: maxW, maxH: maxH)
      imageView.frame = container.bounds
      imageView.autoresizingMask = [.width, .height]
      imageView.image = img
      layoutChrome()
      return
    }

    guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
      fail(message: "no image source")
      return
    }

    layoutMedia(container, in: root, mediaSize: NSSize(width: 480, height: 320), maxW: maxW, maxH: maxH)
    imageView.frame = container.bounds
    imageView.autoresizingMask = [.width, .height]
    layoutChrome()

    var request = URLRequest(url: url)
    headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let error {
          self.fail(message: error.localizedDescription)
          return
        }
        guard let data, let img = NSImage(data: data) else {
          self.fail(message: "bad image data")
          return
        }
        self.layoutMedia(container, in: root, mediaSize: img.size, maxW: maxW, maxH: maxH)
        imageView.frame = container.bounds
        imageView.image = img
        self.layoutChrome()
      }
    }.resume()
  }

  private func presentVideo(
    path: String?,
    urlString: String?,
    headers: [String: String]?,
    maxW: CGFloat,
    maxH: CGFloat,
    in container: NSView,
    root: NSView
  ) {
    let asset: AVURLAsset?
    if let path, !path.isEmpty {
      asset = AVURLAsset(url: URL(fileURLWithPath: path))
    } else if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
      var options: [String: Any] = [:]
      if let headers, !headers.isEmpty {
        options["AVURLAssetHTTPHeaderFieldsKey"] = headers
      }
      asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
    } else {
      fail(message: "no video source")
      return
    }
    guard let asset else {
      fail(message: "invalid video")
      return
    }

    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    self.player = player
    // Не давать паузе при потере фокуса окна (пересылка / сохранение).
    player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in
      guard let self, self.appUiRaised, let p = self.player, p.rate == 0,
            let item = p.currentItem, item.status == .readyToPlay
      else { return }
      let t = p.currentTime()
      let d = item.duration
      if d.isNumeric, t.isNumeric, CMTimeCompare(t, d) >= 0 { return }
      p.play()
    }

    let pv = AVPlayerView(frame: .zero)
    // По умолчанию без контролов; при hover → .inline (см. onMediaHoverChanged).
    pv.controlsStyle = .none
    pv.showsFullScreenToggleButton = false
    pv.videoGravity = .resizeAspect
    pv.player = player
    pv.wantsLayer = true
    pv.layer?.backgroundColor = NSColor.clear.cgColor
    pv.layer?.cornerRadius = 8
    pv.layer?.masksToBounds = true
    playerView = pv
    container.addSubview(pv)
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor

    let applySize: (CGFloat, CGFloat) -> Void = { [weak self] w, h in
      guard let self, w > 1, h > 1 else { return }
      self.layoutMedia(
        container,
        in: root,
        mediaSize: NSSize(width: w, height: h),
        maxW: maxW,
        maxH: maxH
      )
      pv.frame = container.bounds
      self.layoutChrome()
    }

    layoutMedia(container, in: root, mediaSize: NSSize(width: 1280, height: 720), maxW: maxW, maxH: maxH)
    pv.frame = container.bounds
    pv.autoresizingMask = [.width, .height]
    layoutChrome()
    player.play()

    statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
      if item.status == .failed {
        DispatchQueue.main.async {
          self?.fail(message: item.error?.localizedDescription ?? "playback failed")
        }
        return
      }
      guard item.status == .readyToPlay else { return }
      let ps = item.presentationSize
      DispatchQueue.main.async {
        if ps.width > 1, ps.height > 1 {
          applySize(ps.width, ps.height)
        }
      }
    }

    asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
      var error: NSError?
      let status = asset.statusOfValue(forKey: "tracks", error: &error)
      guard status == .loaded else { return }
      guard let track = asset.tracks(withMediaType: .video).first else { return }
      let size = track.naturalSize.applying(track.preferredTransform)
      DispatchQueue.main.async {
        applySize(abs(size.width), abs(size.height))
      }
    }
  }

  private func presentPdf(
    path: String?,
    maxW: CGFloat,
    maxH: CGFloat,
    in container: NSView,
    root: NSView
  ) {
    guard let path, !path.isEmpty, let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
      fail(message: "no pdf")
      return
    }
    let pdfView = PDFView(frame: .zero)
    pdfView.document = doc
    pdfView.autoScales = true
    pdfView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    pdfView.wantsLayer = true
    pdfView.layer?.cornerRadius = 12
    pdfView.layer?.masksToBounds = true
    container.addSubview(pdfView)
    layoutMedia(container, in: root, mediaSize: NSSize(width: maxW, height: maxH), maxW: maxW, maxH: maxH)
    pdfView.frame = container.bounds
    pdfView.autoresizingMask = [.width, .height]
    layoutChrome()
  }

  private func presentText(
    text: String?,
    path: String?,
    maxW: CGFloat,
    maxH: CGFloat,
    in container: NSView,
    root: NSView
  ) {
    var content = text ?? ""
    if content.isEmpty, let path, !path.isEmpty {
      content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    if content.isEmpty {
      fail(message: "no text")
      return
    }

    let scroll = NSScrollView(frame: .zero)
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = 12
    scroll.layer?.masksToBounds = true

    let textView = NSTextView()
    textView.isEditable = false
    textView.isSelectable = true
    textView.string = content
    textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textColor = .white
    textView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    textView.autoresizingMask = [.width]
    scroll.documentView = textView

    container.addSubview(scroll)
    layoutMedia(container, in: root, mediaSize: NSSize(width: maxW, height: maxH), maxW: maxW, maxH: maxH)
    scroll.frame = container.bounds
    scroll.autoresizingMask = [.width, .height]
    textView.frame = NSRect(origin: .zero, size: scroll.contentSize)
    layoutChrome()
  }

  private func layoutMedia(
    _ container: NSView,
    in root: NSView,
    mediaSize: NSSize,
    maxW: CGFloat,
    maxH: CGFloat
  ) {
    var w = mediaSize.width
    var h = mediaSize.height
    if w < 1 { w = 640 }
    if h < 1 { h = 360 }
    let scale = min(maxW / w, maxH / h, 1.0)
    w *= scale
    h *= scale

    // Строго по центру экрана компьютера.
    let x = (root.bounds.width - w) / 2
    let y = (root.bounds.height - h) / 2
    let frame = NSRect(x: x, y: y, width: w, height: h)
    baseMediaFrame = frame
    zoomScale = 1.0
    container.frame = frame
  }

  private func installKeyMonitor() {
    removeKeyMonitor()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        self?.close(success: true)
        return nil
      }
      return event
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func fail(message: String) {
    let callback = pendingResult
    pendingResult = nil
    completed = true
    tearDown()
    callback?(FlutterError(code: "SHOW_FAILED", message: message, details: nil))
  }

  private func close(success: Bool) {
    if completed {
      tearDown()
      return
    }
    completed = true
    let callback = pendingResult
    pendingResult = nil
    tearDown()
    if success { callback?(nil) }
  }

  private func tearDown() {
    if appUiRaised {
      restoreOverlayAboveApp()
    }
    removeKeyMonitor()
    statusObserver?.invalidate()
    statusObserver = nil
    player?.pause()
    playerView?.player = nil
    playerView = nil
    player = nil
    metaView = nil
    chatLabel = nil
    dateLabel = nil
    toolbarView = nil
    mediaContainer = nil
    rootView = nil
    if let window = overlayWindow {
      window.delegate = nil
      window.orderOut(nil)
      window.close()
    }
    overlayWindow = nil
  }

  func windowWillClose(_ notification: Notification) {
    close(success: true)
  }

  private static var targetScreen: NSScreen? {
    if let w = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      return w.screen ?? NSScreen.main
    }
    return NSScreen.main ?? NSScreen.screens.first
  }
}

private final class OverlayRootView: NSView {
  var onBackdropClick: (() -> Void)?
  var onMediaHoverChanged: ((Bool) -> Void)?
  var isAppUiRaised: (() -> Bool)?
  weak var mediaView: NSView?

  private var tracking: NSTrackingArea?
  private var mediaHovering = false

  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    tracking = area
  }

  override func mouseExited(with event: NSEvent) {
    setMediaHover(false)
  }

  override func mouseMoved(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    let overMedia = mediaView?.frame.contains(p) == true
    setMediaHover(overMedia)
  }

  override func mouseDown(with event: NSEvent) {
    let p = convert(event.locationInWindow, from: nil)
    if let media = mediaView, media.frame.contains(p) {
      // Клик по видео при открытой пересылке — закрыть пересылку.
      if isAppUiRaised?() == true {
        onBackdropClick?()
      }
      return
    }
    // Клик по тулбару — не закрываем медиа (и не глотаем «Переслать»).
    for sub in subviews {
      if sub is NSStackView, sub.frame.contains(p) { return }
    }
    onBackdropClick?()
  }

  private func setMediaHover(_ value: Bool) {
    guard mediaHovering != value else { return }
    mediaHovering = value
    onMediaHoverChanged?(value)
  }
}
