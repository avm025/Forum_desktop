import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Если leaf Let's Encrypt на 4um.me истёк — Dart рвёт handshake.
/// Принимаем только наши хосты и CN=*4um.me (не любой чужой сертификат).
HttpClient createForumRawHttpClient() {
  final client = HttpClient();
  // Без таймаутов handshake на Windows может висеть бесконечно.
  client.connectionTimeout = const Duration(seconds: 15);
  client.idleTimeout = const Duration(seconds: 30);
  client.badCertificateCallback = (cert, host, port) {
    const allowed = {'4um.me', 'webrtc.4um.me', 'livekit.4um.me'};
    if (!allowed.contains(host)) return false;
    final subject = cert.subject;
    return subject.contains('4um.me');
  };
  return client;
}

http.Client createForumHttpClient() => IOClient(createForumRawHttpClient());

Future<WebSocketChannel> connectForumWebSocket(Uri uri) async {
  final channel = IOWebSocketChannel.connect(
    _normalizeWsUri(uri),
    customClient: createForumRawHttpClient(),
  );
  return channel;
}

/// Call signaling: явный HTTP/1.1 Upgrade через [WebSocket.connect]
/// (иначе прокси может рвать handshake на HTTP/2).
Future<WebSocketChannel> connectCallSignalingWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  final normalized = _normalizeWsUri(uri);
  final socket = await WebSocket.connect(
    normalized.toString(),
    customClient: createForumRawHttpClient(),
    headers: {
      'Origin': 'https://4um.me',
      ...?headers,
    },
  );
  return IOWebSocketChannel(socket);
}

/// wss://host/path без порта → Uri.port == 0 → Dart может слать :0 (400).
Uri _normalizeWsUri(Uri uri) {
  if (uri.hasPort && uri.port != 0) return uri;
  final scheme = uri.scheme.toLowerCase();
  final port = (scheme == 'https' || scheme == 'wss')
      ? 443
      : (scheme == 'http' || scheme == 'ws')
          ? 80
          : 443;
  return uri.replace(port: port);
}

Future<void> awaitWebSocketReady(WebSocketChannel channel) => channel.ready;

/// Закрытие WS при sleep/quit — сервер сразу offline для FCM.
Future<void> forceCloseWebSocket(WebSocketChannel? channel) async {
  if (channel == null) return;
  try {
    await channel.sink
        .close(WebSocketStatus.goingAway)
        .timeout(const Duration(milliseconds: 800));
  } catch (_) {}
}
