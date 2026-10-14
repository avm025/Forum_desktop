import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'calls/call_manager.dart';
import 'services/api_logger.dart';
import 'services/desktop_notification_service.dart';
import 'services/firebase_service.dart';
import 'screens/auth/phone_login_screen.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_colors.dart';
import 'widgets/call/call_host_overlay.dart';

const _lifecycleChannel = MethodChannel('forum.me/lifecycle');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiLogger.instance.init();
  // Не блокируем первый кадр на APNs/FCM — иначе чёрное окно до runApp.
  unawaited(FirebaseService.instance.initialize());
  unawaited(DesktopNotificationService.instance.initialize());
  runApp(const ForumApp());
}

class ForumApp extends StatelessWidget {
  const ForumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final state = AppState();
            _lifecycleChannel.setMethodCallHandler((call) async {
              // Явный if — гарантированно один путь; result уходит в native после await.
              if (call.method == 'willTerminate') {
                await state.prepareForTerminate();
                return true;
              }
              if (call.method == 'willSleep') {
                await state.prepareForSleep();
                return true;
              }
              if (call.method == 'didWake') {
                await state.prepareForWake();
                return true;
              }
              // Крестик → Dock: не рвать WS, только «не в фокусе» для баннеров.
              if (call.method == 'windowHidden') {
                state.onWindowHiddenToDock();
                return true;
              }
              if (call.method == 'windowShown') {
                state.onWindowShownFromDock();
                return true;
              }
              throw PlatformException(
                code: 'unimplemented',
                message: call.method,
              );
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              state.initialize();
            });
            return state;
          },
        ),
        ChangeNotifierProvider.value(value: CallManager.instance),
        ChangeNotifierProvider.value(value: ApiLogger.instance),
      ],
      child: Consumer<AppState>(
        builder: (context, state, _) {
          // Key сбрасывает Navigator после входа — иначе стек Phone→QR→SMS
          // остаётся поверх нового home и крутит спиннер навсегда.
          return MaterialApp(
            key: ValueKey(
              'auth_${state.authReady}_${state.isAuthenticated}',
            ),
            title: 'Forum',
            debugShowCheckedModeBanner: false,
            theme: state.lightTheme,
            darkTheme: state.darkTheme,
            themeMode: state.themeMode,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(state.textScaleFactor),
                ),
                child: CallHostOverlay(
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: !state.authReady
                ? const _AuthSplash()
                : state.isAuthenticated
                    ? const HomeScreen()
                    : const PhoneLoginScreen(),
          );
        },
      ),
    );
  }
}

class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF4F4F5),
      body: Center(
        child: CircularProgressIndicator(color: AppColors.purple),
      ),
    );
  }
}
