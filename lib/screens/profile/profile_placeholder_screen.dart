import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Заглушка для разделов профиля, ещё не перенесённых с iOS.
class ProfilePlaceholderScreen extends StatelessWidget {
  final String title;

  const ProfilePlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final stateBg = Theme.of(context).brightness == Brightness.dark
        ? p.bg1
        : const Color(0xFFF4F5F7);

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Раздел «$title» появится позже',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.text2, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
