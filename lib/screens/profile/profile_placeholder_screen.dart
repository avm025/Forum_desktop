import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Заглушка для разделов профиля, ещё не перенесённых с iOS.
/// [embedded] — правая панель профиля без отдельного Scaffold.
class ProfilePlaceholderScreen extends StatelessWidget {
  final String title;
  final bool embedded;

  const ProfilePlaceholderScreen({
    super.key,
    required this.title,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stateBg = Theme.of(context).brightness == Brightness.dark
        ? p.bg1
        : const Color(0xFFF4F5F7);

    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Раздел «$title» появится позже',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.text2, fontSize: 15),
        ),
      ),
    );

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  color: p.text1,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: stateBg,
      appBar: AppBar(
        backgroundColor: stateBg,
        elevation: 0,
        foregroundColor: p.text1,
        title: Text(
          title,
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: body,
    );
  }
}
