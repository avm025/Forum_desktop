import Cocoa
import FlutterMacOS

/// Курсор + перехват Cmd+V для картинок из буфера (скрины).
///
/// ⇧⌘4 → Desktop (файл) — DnD ок.
/// ⌃⇧⌘4 / «Save to Clipboard» → TIFF в pasteboard — без перехвата Flutter виснет.
///
/// Пайплайн: на main только dump сырых байт во temp (без decode),
/// ресайз через `/usr/bin/sips` в background.
class ForumCursorPlugin: NSObject, FlutterPlugin {
  private weak var flutterView: NSView?
  private var channel: FlutterMethodChannel?
  private var keyMonitor: Any?
  private var imagePasteInterceptEnabled = false
  private var pasteInFlight = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/cursor",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumCursorPlugin()
    instance.channel = channel
    instance.flutterView = registrar.view
    registrar.addMethodCallDelegate(instance, channel: channel)
    _instance = instance
    // Монитор всегда установлен; глотаем Cmd+V только при enabled.
    instance.installKeyMonitorIfNeeded()
  }

  static func attach(flutterView: NSView) {
    _instance?.flutterView = flutterView
  }

  private static weak var _instance: ForumCursorPlugin?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPosition":
      result(cursorSnapshot())

    case "hasClipboardImage":
      result(Self.pasteboardHasImage())

    case "saveClipboardImage":
      beginSaveClipboardImage(result: result)

    case "setImagePasteIntercept":
      imagePasteInterceptEnabled = (call.arguments as? Bool) ?? false
      if imagePasteInterceptEnabled {
        installKeyMonitorIfNeeded()
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installKeyMonitorIfNeeded() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self = self else { return event }
      return self.handleKeyDown(event)
    }
  }

  private func removeKeyMonitor() {
    if let monitor = keyMonitor {
      NSEvent.removeMonitor(monitor)
      keyMonitor = nil
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard imagePasteInterceptEnabled else { return event }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isOnlyCmd = flags.contains(.command)
      && !flags.contains(.option)
      && !flags.contains(.control)
      && !flags.contains(.shift)
    let isV = event.charactersIgnoringModifiers?.lowercased() == "v"
    guard isOnlyCmd && isV else { return event }

    // Типы без загрузки байт — дёшево.
    guard Self.pasteboardHasImage() else { return event }

    if pasteInFlight {
      return nil
    }
    pasteInFlight = true

    // Dump на диск на main (без NSImage/NSBitmapImageRep).
    let rawPath = Self.dumpPasteboardImageToTempFile()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let saved = rawPath.flatMap { Self.sipsToJpeg(inputPath: $0) }
      if let rawPath, rawPath.contains("forum_clip_raw_") {
        try? FileManager.default.removeItem(atPath: rawPath)
      }
      DispatchQueue.main.async {
        self?.pasteInFlight = false
        self?.channel?.invokeMethod("onClipboardImage", arguments: saved)
      }
    }

    return nil
  }

  private func beginSaveClipboardImage(result: @escaping FlutterResult) {
    let rawPath = Self.dumpPasteboardImageToTempFile()
    if rawPath == nil {
      result(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let saved = Self.sipsToJpeg(inputPath: rawPath!)
      if rawPath!.contains("forum_clip_raw_") {
        try? FileManager.default.removeItem(atPath: rawPath!)
      }
      DispatchQueue.main.async {
        result(saved)
      }
    }
  }

  private func cursorSnapshot() -> [String: Any]? {
    guard let view = flutterView ?? NSApp.keyWindow?.contentView,
          let window = view.window else {
      return nil
    }
    let screenPoint = NSEvent.mouseLocation
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let viewPoint = view.convert(windowPoint, from: nil)
    let y = view.bounds.height - viewPoint.y
    let primaryDown = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
    return [
      "x": Double(viewPoint.x),
      "y": Double(y),
      "primaryDown": primaryDown,
    ]
  }

  private static func pasteboardHasImage() -> Bool {
    let pb = NSPasteboard.general
    guard let types = pb.types else { return false }
    let wanted: Set<NSPasteboard.PasteboardType> = [
      .tiff,
      .png,
      NSPasteboard.PasteboardType("public.jpeg"),
      NSPasteboard.PasteboardType("public.jpeg-2000"),
      NSPasteboard.PasteboardType("public.heic"),
      NSPasteboard.PasteboardType("public.file-url"),
    ]
    return types.contains { wanted.contains($0) }
  }

  /// Только I/O pasteboard → файл. Без decode (decode = hang на Retina TIFF).
  private static func dumpPasteboardImageToTempFile() -> String? {
    let pb = NSPasteboard.general
    let dir = NSTemporaryDirectory()
    let id = Int(Date().timeIntervalSince1970 * 1000)

    // 1) Уже файл на диске (копировали PNG с Desktop) — путь, без чтения.
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
      .urlReadingFileURLsOnly: true,
    ]) as? [URL] {
      for url in urls {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "tif", "tiff", "heic", "gif", "webp"]
          .contains(ext) else { continue }
        if FileManager.default.fileExists(atPath: url.path) {
          return url.path
        }
      }
    }

    // 2) PNG раньше TIFF — у скрина в буфере часто оба, PNG меньше.
    let candidates: [(NSPasteboard.PasteboardType, String)] = [
      (.png, "png"),
      (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
      (NSPasteboard.PasteboardType("public.heic"), "heic"),
      (.tiff, "tiff"),
    ]

    for (type, ext) in candidates {
      guard let data = pb.data(forType: type), !data.isEmpty else { continue }
      let path = (dir as NSString).appendingPathComponent(
        "forum_clip_raw_\(id).\(ext)"
      )
      do {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
      } catch {
        continue
      }
    }
    return nil
  }

  /// Ресайз/JPEG только через sips — без NSBitmapImageRep в нашем процессе.
  private static func sipsToJpeg(inputPath: String) -> [String: Any]? {
    let maxSide = 1280
    let quality = 50
    let name = "forum_clip_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    let outPath = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(name)

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = [
      "-Z", "\(maxSide)",
      "-s", "format", "jpeg",
      "-s", "formatOptions", "\(quality)",
      inputPath,
      "--out", outPath,
    ]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
      try proc.run()
      proc.waitUntilExit()
    } catch {
      return nil
    }

    guard proc.terminationStatus == 0,
          FileManager.default.fileExists(atPath: outPath),
          let jpeg = try? Data(contentsOf: URL(fileURLWithPath: outPath)),
          !jpeg.isEmpty else {
      return nil
    }

    let dims = sipsPixelSize(outPath)
    return [
      "path": outPath,
      "width": dims.0,
      "height": dims.1,
      "size": jpeg.count,
      "fileName": name,
    ]
  }

  private static func sipsPixelSize(_ path: String) -> (String, String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-g", "pixelWidth", "-g", "pixelHeight", path]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
      try proc.run()
      proc.waitUntilExit()
    } catch {
      return ("", "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8) ?? ""
    let w = matchInt(out, key: "pixelWidth")
    let h = matchInt(out, key: "pixelHeight")
    return (w, h)
  }

  private static func matchInt(_ text: String, key: String) -> String {
    guard let regex = try? NSRegularExpression(
      pattern: "\(key):\\s*(\\d+)"
    ) else { return "" }
    let range = NSRange(text.startIndex..., in: text)
    guard let m = regex.firstMatch(in: text, range: range),
          let r = Range(m.range(at: 1), in: text) else { return "" }
    return String(text[r])
  }

  deinit {
    removeKeyMonitor()
  }
}
