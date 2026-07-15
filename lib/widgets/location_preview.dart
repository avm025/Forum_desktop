import 'package:flutter/material.dart';

import '../models/message_view_model.dart';
import '../theme/app_theme.dart';

/// Превью геопозиции (latitude/longitude/address) без внешних карт —
/// стилизованная подложка с пином и адресом.
class LocationPreview extends StatelessWidget {
  final MessageViewModel message;
  const LocationPreview({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2B3A2B), Color(0xFF1C2A1C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Icon(Icons.location_on, color: p.purple, size: 40),
              ),
            ),
            Container(
              width: double.infinity,
              color: p.bg3,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.address ?? 'Геопозиция',
                    style: TextStyle(
                      color: p.text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${message.latitude?.toStringAsFixed(4)}, '
                    '${message.longitude?.toStringAsFixed(4)}',
                    style: TextStyle(color: p.text2, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
