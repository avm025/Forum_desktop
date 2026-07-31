import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web / WASM: стандартное подключение без dart:io.
http.Client createForumHttpClient() => http.Client();

WebSocketChannel connectForumWebSocket(Uri uri) => WebSocketChannel.connect(uri);

Future<WebSocketChannel> connectCallSignalingWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  final channel = WebSocketChannel.connect(uri);
  try {
    await channel.ready;
  } catch (_) {}
  return channel;
}

Future<void> awaitWebSocketReady(WebSocketChannel channel) async {
  // На web ready может отсутствовать — подключение уже установлено.
  try {
    await channel.ready;
  } catch (_) {}
}
