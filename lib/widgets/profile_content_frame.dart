import 'package:flutter/material.dart';

/// Общие отступы и ширина блоков профиля (свой и собеседника).
class ProfileLayout {
  /// Базовая ширина 480 + 15%.
  static const maxContentWidth = 552.0;
  static const horizontalInset = 16.0;
}

/// Центрирует контент профиля и ограничивает ширину в широком окне.
class ProfileContentFrame extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ProfileContentFrame({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ProfileLayout.horizontalInset,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ProfileLayout.maxContentWidth,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
