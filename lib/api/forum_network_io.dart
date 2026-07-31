import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

http.Client createForumHttpClient() => IOClient(HttpClient());

WebSocketChannel connectForumWebSocket(Uri uri) {
  return IOWebSocketChannel.connect(uri, customClient: HttpClient());
}

/// Call signaling: явный HTTP/1.1 Upgrade через [WebSocket.connect]
/// (иначе nginx:8088 рвёт handshake на HTTP/2).
Future<WebSocketChannel> connectCallSignalingWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  final socket = await WebSocket.connect(
    uri.toString(),
    headers: {
      'Origin': 'https://4um.me',
      ...?headers,
    },
  );
  return IOWebSocketChannel(socket);
}

Future<void> awaitWebSocketReady(WebSocketChannel channel) => channel.ready;
