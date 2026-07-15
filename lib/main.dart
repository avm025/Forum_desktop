import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_logger.dart';
import 'services/firebase_service.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiLogger.instance.init();
  await FirebaseService.instance.initialize();
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              state.initialize();
            });
            return state;
          },
        ),
        ChangeNotifierProvider.value(value: ApiLogger.instance),
      ],
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
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
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
