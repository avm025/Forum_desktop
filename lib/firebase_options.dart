import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase-конфигурация для macOS (из GoogleService-Info.plist).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase не настроен для web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'Firebase настроен только для macOS.',
        );
    }
  }

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAdSJpCmPRgEeLVgivRmt5eCo8Pw8A2MCY',
    appId: '1:899122665561:ios:00ea5a224b4ee071f4f948',
    messagingSenderId: '899122665561',
    projectId: 'forum-cfc88',
    storageBucket: 'forum-cfc88.firebasestorage.app',
    iosBundleId: 'forum.me',
  );
}
