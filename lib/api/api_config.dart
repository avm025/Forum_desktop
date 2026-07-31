/// Конфигурация подключения к серверу Forum.
class ApiConfig {
  ApiConfig._();

  static const String wsHost = 'wss://4um.me:7770';
  static const String httpBase = 'https://4um.me:7770';

  /// Полный путь к файлам в сообщениях: file_server + fdir + fname.
  static const String fileServer = 'https://4um.me/files/';

  /// HTTP API (msg_list и др.).
  static const String httpApiUrl = 'https://4um.me:7770/api/';

  /// Upload медиа/файлов (WS_MSG_MEDIA.md — GL.upload_server).
  static const String uploadServerUrl = 'https://4um.me:7770/api/upload/';

  /// Заголовок Key для HTTP-запросов.
  static const String apiKey = 'Ru*)P(-ro.pro';

  /// JWT текущей сессии (после SMS / QR). Пустой — экран онбординга.
  static String _sessionToken = '';

  static String get token => _sessionToken;

  static bool get hasSession => _sessionToken.trim().isNotEmpty;

  static void setSessionToken(String? value) {
    _sessionToken = value?.trim() ?? '';
  }

  /// WS URL: с JWT после входа, без `key` на экране QR.
  static Uri get wsUri {
    final t = token;
    if (t.isEmpty) return Uri.parse(wsHost);
    return Uri.parse('$wsHost?key=${Uri.encodeQueryComponent(t)}');
  }

  static Uri get httpApiUri => Uri.parse(httpApiUrl);
  static Uri get uploadServerUri => Uri.parse(uploadServerUrl);

  static Map<String, String> get authHeaders => {
        'Content-Type': 'application/json; charset=utf-8',
        if (hasSession) 'Authorization': 'Bearer $token',
        'Key': apiKey,
      };

  /// Control-plane WebSocket для звонков (Forum CallModule / SignalingClient).
  /// LiveKit URL/JWT приходят в событии `call.token`.
  static const String callSignalingWs = 'wss://4um.me:8088/ws';

  /// Auth только сообщением `{"type":"auth","payload":{"token":...}}` → `auth.ok`.
  static Uri callSignalingUriForToken(String sessionToken) {
    // Query/Bearer не авторизуют этот сервис — токен в payload после handshake.
    return Uri.parse(callSignalingWs);
  }

  /// HTTP без Bearer: `sms`, `check_code`, `database`.
  static Map<String, String> get openHttpHeaders => {
        'Content-Type': 'application/json; charset=utf-8',
        'Key': apiKey,
      };

  /// URL аватара/медиа по относительному пути с основного сервера.
  static String mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$httpBase$path';
    return '$httpBase/$path';
  }

  /// URL для отображения файла (upload / ava): CDN `fileServer` или полный http.
  static String resolveAssetUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    final raw = path.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final base = fileServer.endsWith('/') ? fileServer : '$fileServer/';
    if (raw.startsWith('/files/')) return '$base${raw.substring(7)}';
    if (raw.startsWith('files/')) return '$base${raw.substring(6)}';

    final normalized = raw.startsWith('/') ? raw.substring(1) : raw;
    return fileUrl('', normalized);
  }

  /// URL файла в сообщении: file_server + fdir + fname.
  static String fileUrl(String fdir, String fname) {
    if (fname.isEmpty) return '';
    final base = fileServer.endsWith('/') ? fileServer : '$fileServer/';
    final dir = fdir.startsWith('/') ? fdir.substring(1) : fdir;
    final normalizedDir = dir.isEmpty ? '' : (dir.endsWith('/') ? dir : '$dir/');
    return '$base$normalizedDir$fname';
  }
}
