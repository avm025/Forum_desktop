import Cocoa
import FlutterMacOS

/// Позиция курсора в логических координатах Flutter (origin top-left).
class ForumCursorPlugin: NSObject, FlutterPlugin {
  private weak var flutterView: NSView?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "forum_app/cursor",
      binaryMessenger: registrar.messenger
    )
    let instance = ForumCursorPlugin()
    instance.flutterView = registrar.view
    registrar.addMethodCallDelegate(instance, channel: channel)
    _instance = instance
  }

  /// Явно привязать FlutterView (надёжнее, чем registrar.view).
  static func attach(flutterView: NSView) {
    _instance?.flutterView = flutterView
  }

  private static weak var _instance: ForumCursorPlugin?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPosition":
      result(cursorSnapshot())
    default:
      result(FlutterMethodNotImplemented)
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
    // Cocoa: origin bottom-left → Flutter: origin top-left
    let y = view.bounds.height - viewPoint.y
    // Bit 0 = left button; работает и во время native drag.
    let primaryDown = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
    return [
      "x": Double(viewPoint.x),
      "y": Double(y),
      "primaryDown": primaryDown,
    ]
  }
}
