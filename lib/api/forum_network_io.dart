import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

http.Client createForumHttpClient() => IOClient(HttpClient());

WebSocketChannel connectForumWebSocket(Uri uri) {
  return IOWebSocketChannel.connect(uri, customClient: HttpClient());
}

Future<void> awaitWebSocketReady(WebSocketChannel channel) => channel.ready;
