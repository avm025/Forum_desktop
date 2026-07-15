import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Разделитель с датой между сообщениями ("24 августа").
class DateSeparator extends StatelessWidget {
  final String label;
  const DateSeparator({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: p.text2,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
