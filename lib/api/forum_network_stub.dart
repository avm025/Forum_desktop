import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web / WASM: стандартное подключение без dart:io.
http.Client createForumHttpClient() => http.Client();

WebSocketChannel connectForumWebSocket(Uri uri) => WebSocketChannel.connect(uri);

Future<void> awaitWebSocketReady(WebSocketChannel channel) async {
  // На web ready может отсутствовать — подключение уже установлено.
  try {
    await channel.ready;
  } catch (_) {}
}
