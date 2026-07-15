import 'dart:math';

/// Клиентский hash сообщения (40 hex) — id скелета до эха сервера.
class ClientMsgHash {
  ClientMsgHash._();

  static final _random = Random.secure();

  static String generate() {
    return List.generate(40, (_) => _random.nextInt(16).toRadixString(16))
        .join();
  }
}
