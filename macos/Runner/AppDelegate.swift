import Cocoa
import FlutterMacOS
import FirebaseMessaging
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  /// Sandbox: только контейнер приложения.
  private lazy var apnsLogURL: URL = {
    let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("Logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("forum_apns.log")
  }()

  override init() {
    super.init()
    fputs("Forum APNs: AppDelegate.init\n", stderr)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onAppDidFinishLaunching(_:)),
      name: NSApplication.didFinishLaunchingNotification,
      object: nil
    )
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(
      self,
      selector: #selector(onWillSleep(_:)),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspace.addObserver(
      self,
      selector: #selector(onDidWake(_:)),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
  }

  @objc private func onWillSleep(_ note: Notification) {
    apnsLog("NSWorkspace.willSleep → disconnect WS for FCM")
    // Важно дождаться Dart: иначе процесс засыпает с открытым WS,
    // сервер считает online и шлёт FCM только после реального обрыва (часто на wake).
    invokeLifecycleAndWait("willSleep", timeoutSeconds: 1.5)
  }

  @objc private func onDidWake(_ note: Notification) {
    apnsLog("NSWorkspace.didWake → reconnect WS")
    invokeLifecycle("didWake")
  }

  private func invokeLifecycle(_ method: String) {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      apnsLog("lifecycle \(method): no FlutterViewController")
      return
    }
    FlutterMethodChannel(
      name: "forum.me/lifecycle",
      binaryMessenger: controller.engine.binaryMessenger
    ).invokeMethod(method, arguments: nil)
  }

  /// Вызов Dart и прокачка RunLoop, пока не придёт result (или timeout).
  private func invokeLifecycleAndWait(_ method: String, timeoutSeconds: TimeInterval) {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      apnsLog("lifecycle \(method): no FlutterViewController")
      return
    }
    let channel = FlutterMethodChannel(
      name: "forum.me/lifecycle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    var done = false
    channel.invokeMethod(method, arguments: nil) { result in
      done = true
      if let err = result as? FlutterError {
        self.apnsLog("lifecycle \(method) error: \(err.message ?? "")")
      } else {
        self.apnsLog("lifecycle \(method) dart ok")
      }
    }
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while !done && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    if !done {
      apnsLog("lifecycle \(method) TIMEOUT — WS мог остаться online")
    }
  }

  @objc private func onAppDidFinishLaunching(_ note: Notification) {
    apnsLog("NSApplication.didFinishLaunchingNotification")
    registerBadgeChannel()
    registerForApns(reason: "notification")
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    apnsLog("applicationDidFinishLaunching(delegate)")
    // Firebase.configure — только из Dart (FlutterFire). Здесь не дублируем.
    super.applicationDidFinishLaunching(notification)

    NSApp.setActivationPolicy(.regular)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    registerBadgeChannel()
    registerForApns(reason: "delegate")
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      self?.apnsLog(
        "after 5s isRegistered=\(NSApp.isRegisteredForRemoteNotifications)"
      )
    }
  }

  /// Dock badge: число непрочитанных (Telegram-style).
  private func registerBadgeChannel() {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return }
    FlutterMethodChannel(
      name: "forum.me/badge",
      binaryMessenger: controller.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "setBadge" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count: Int
      if let n = call.arguments as? Int {
        count = n
      } else if let n = call.arguments as? NSNumber {
        count = n.intValue
      } else {
        count = 0
      }
      DispatchQueue.main.async {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : ""
        NSApp.dockTile.display()
      }
      result(nil)
    }
  }

  private func registerForApns(reason: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let center = UNUserNotificationCenter.current()
      center.delegate = self
      self.apnsLog(
        "register(\(reason)) isRegistered=\(NSApp.isRegisteredForRemoteNotifications)"
      )
      // Без .alert macOS часто держит push.types=0 → FCM «успех», баннера нет.
      center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if let error {
          self.apnsLog("requestAuthorization error: \(error.localizedDescription)")
        }
        self.apnsLog("requestAuthorization granted=\(granted)")
        center.getNotificationSettings { settings in
          self.apnsLog(
            "settings status=\(settings.authorizationStatus.rawValue) "
              + "alert=\(settings.alertSetting.rawValue) "
              + "banner=\(settings.alertStyle.rawValue) "
              + "sound=\(settings.soundSetting.rawValue)"
          )
        }
        DispatchQueue.main.async {
          NSApp.registerForRemoteNotifications()
        }
      }
    }
  }

  /// Показать баннер через UNUserNotificationCenter (обход «тихого» remote path).
  private func presentLocalBanner(title: String, body: String, id: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(req) { error in
      if let error {
        self.apnsLog("localBanner error: \(error.localizedDescription)")
      } else {
        self.apnsLog("localBanner scheduled title=\(title)")
      }
    }
  }

  private func alertText(from userInfo: [String: Any]) -> (String, String)? {
    let aps = userInfo["aps"] as? [String: Any]
    if let alert = aps?["alert"] as? String, !alert.isEmpty {
      return ("Forum", alert)
    }
    if let alert = aps?["alert"] as? [String: Any] {
      let title = (alert["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "Forum"
      let body = (alert["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? (alert["loc-key"] as? String) ?? ""
      if !body.isEmpty || title != "Forum" {
        return (title.isEmpty ? "Forum" : title, body.isEmpty ? "Новое уведомление" : body)
      }
    }
    // FCM иногда кладёт текст вне aps.
    let title = (userInfo["gcm.notification.title"] as? String)
      ?? (userInfo["title"] as? String) ?? "Forum"
    let body = (userInfo["gcm.notification.body"] as? String)
      ?? (userInfo["body"] as? String) ?? ""
    if !body.isEmpty {
      return (title, body)
    }
    return nil
  }

  /// Баннер даже когда приложение открыто (как Forum_ios willPresent).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    apnsLog("willPresent id=\(notification.request.identifier)")
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    apnsLog("didReceiveResponse id=\(response.notification.request.identifier)")
    completionHandler()
  }

  /// Не вызывать `super`: GULAppDelegateSwizzler подменяет IMP, и super падает с
  /// unrecognized selector. Токен отдаём в FIRMessaging сами.
  override func application(
    _ application: NSApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsLog("didRegister bytes=\(deviceToken.count) hexPrefix=\(hex.prefix(16))…")
  }

  override func application(
    _ application: NSApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apnsLog("didFail: \(error.localizedDescription)")
  }

  /// Диагностика: дошёл ли APNs/FCM до процесса (в т.ч. когда UI уже не жив).
  override func application(
    _ application: NSApplication,
    didReceiveRemoteNotification userInfo: [String: Any]
  ) {
    let keys = userInfo.keys.map { "\($0)" }.sorted().joined(separator: ",")
    let aps = userInfo["aps"] as? [String: Any]
    let apsDesc = String(describing: aps ?? [:])
    let hasAlert = aps?["alert"] != nil || userInfo["notification"] != nil
    apnsLog(
      "didReceiveRemoteNotification keys=[\(keys)] hasAlert=\(hasAlert) aps=\(apsDesc)"
    )
    // Видимое окно в фокусе — баннеры решает Flutter. Иначе (Dock / фон)
    // дублируем remote alert локально: isActive бывает true без окон.
    let windowVisible = mainFlutterWindow?.isVisible == true
    guard !(NSApp.isActive && windowVisible) else {
      apnsLog("skip native localBanner: window focused")
      return
    }
    if let (title, body) = alertText(from: userInfo) {
      presentLocalBanner(
        title: title,
        body: body,
        id: "forum.remote.\(UUID().uuidString)"
      )
    } else {
      presentLocalBanner(
        title: "Forum",
        body: "Входящий push (без текста alert)",
        id: "forum.remote.\(UUID().uuidString)"
      )
    }
  }

  /// Quit с отложенным terminate: Flutter успевает закрыть WS,
  /// иначе сервер считает Mac online и не шлёт FCM.
  /// (applicationWillTerminate + semaphore почти всегда TIMEOUT — движок уже гаснет.)
  private var terminateDisconnectStarted = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminateDisconnectStarted {
      return .terminateNow
    }
    terminateDisconnectStarted = true
    apnsLog("applicationShouldTerminate → disconnect WS (terminateLater)")

    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      apnsLog("lifecycle willTerminate: no FlutterViewController")
      return .terminateNow
    }

    let channel = FlutterMethodChannel(
      name: "forum.me/lifecycle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    var replied = false
    let replyOnce: () -> Void = {
      guard !replied else { return }
      replied = true
      NSApp.reply(toApplicationShouldTerminate: true)
    }

    channel.invokeMethod("willTerminate", arguments: nil) { result in
      if let err = result as? FlutterError {
        self.apnsLog("lifecycle willTerminate error: \(err.message ?? "")")
      } else {
        self.apnsLog("lifecycle willTerminate dart ok")
      }
      DispatchQueue.main.async(execute: replyOnce)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      if !replied {
        self.apnsLog("lifecycle willTerminate TIMEOUT — forcing quit (WS мог остаться online)")
        replyOnce()
      }
    }
    return .terminateLater
  }

  override func applicationWillTerminate(_ notification: Notification) {
    apnsLog("applicationWillTerminate")
    super.applicationWillTerminate(notification)
  }

  /// Крестик только скрывает окно; процесс остаётся в Dock.
  /// Полный выход: Cmd+Q → applicationShouldTerminate (закрывает WS).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Окно в Dock: WS остаётся (как Telegram) — баннеры из живого msg.
  /// FCM нужен только при sleep / Cmd+Q, не при hide.
  func onMainWindowHiddenForPush() {
    apnsLog("main window hidden → keep WS, banners via local notify")
    invokeLifecycle("windowHidden")
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      apnsLog("reopen from Dock → foreground")
      invokeLifecycle("windowShown")
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func apnsLog(_ line: String) {
    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    fputs("Forum APNs: \(line)\n", stderr)
    NSLog("Forum APNs: %@", line)
    if let data = stamped.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: apnsLogURL.path) {
        if let handle = try? FileHandle(forWritingTo: apnsLogURL) {
          defer { try? handle.close() }
          handle.seekToEndOfFile()
          handle.write(data)
        }
      } else {
        try? data.write(to: apnsLogURL)
      }
    }
  }
}
