import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:forum_app/screens/home_screen.dart';
import 'package:forum_app/state/app_state.dart';
import 'package:forum_app/theme/app_theme.dart';

void main() {
  testWidgets('Forum app builds and shows the chats title',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Чаты'), findsOneWidget);
  });
}
