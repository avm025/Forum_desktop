import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Если leaf Let's Encrypt на 4um.me истёк — Dart рвёт handshake.
/// Принимаем только наши хосты и CN=*4um.me (не любой чужой сертификат).
HttpClient createForumRawHttpClient() {
  final client = HttpClient();
  client.badCertificateCallback = (cert, host, port) {
    const allowed = {'4um.me', 'webrtc.4um.me', 'livekit.4um.me'};
    if (!allowed.contains(host)) return false;
    final subject = cert.subject;
    return subject.contains('4um.me');
  };
  return client;
}

http.Client createForumHttpClient() => IOClient(createForumRawHttpClient());

WebSocketChannel connectForumWebSocket(Uri uri) {
  return IOWebSocketChannel.connect(
    uri,
    customClient: createForumRawHttpClient(),
  );
}

/// Call signaling: явный HTTP/1.1 Upgrade через [WebSocket.connect]
/// (иначе прокси может рвать handshake на HTTP/2).
Future<WebSocketChannel> connectCallSignalingWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  final socket = await WebSocket.connect(
    uri.toString(),
    customClient: createForumRawHttpClient(),
    headers: {
      'Origin': 'https://4um.me',
      ...?headers,
    },
  );
  return IOWebSocketChannel(socket);
}

Future<void> awaitWebSocketReady(WebSocketChannel channel) => channel.ready;
