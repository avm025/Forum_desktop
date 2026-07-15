import Cocoa
import FlutterMacOS
import PDFKit

class ForumPdfViewFactory: NSObject, FlutterPlatformViewFactory {
  private var messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withViewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> NSView {
    return ForumPdfPlatformView(frame: .zero, args: args)
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

class ForumPdfPlatformView: NSView {
  private let pdfView = PDFView()

  init(frame: NSRect, args: Any?) {
    super.init(frame: frame)
    wantsLayer = true

    pdfView.translatesAutoresizingMaskIntoConstraints = false
    pdfView.autoScales = true
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical
    addSubview(pdfView)

    NSLayoutConstraint.activate([
      pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
      pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
      pdfView.topAnchor.constraint(equalTo: topAnchor),
      pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    if let params = args as? [String: Any],
       let path = params["path"] as? String {
      let url = URL(fileURLWithPath: path)
      pdfView.document = PDFDocument(url: url)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

class ForumPdfPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = ForumPdfViewFactory(messenger: registrar.messenger)
    registrar.register(factory, withId: "forum/pdf-view")
  }
}
