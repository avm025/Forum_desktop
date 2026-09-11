import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message_view_model.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'live_geo_map.dart';

/// Карта на весь размер окна приложения (как просмотр фото).
class LocationMapDialog extends StatelessWidget {
  final String messageId;
  final String dialogId;
  final double latitude;
  final double longitude;
  final String? address;
  final bool live;

  const LocationMapDialog({
    super.key,
    required this.messageId,
    required this.dialogId,
    required this.latitude,
    required this.longitude,
    this.address,
    this.live = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String messageId,
    required String dialogId,
    required double latitude,
    required double longitude,
    String? address,
    bool live = false,
  }) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Геопозиция',
      barrierColor: Colors.black87,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, __) => Theme(
        data: theme,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: LocationMapDialog(
            messageId: messageId,
            dialogId: dialogId,
            latitude: latitude,
            longitude: longitude,
            address: address,
            live: live,
          ),
        ),
      ),
    );
  }

  MessageViewModel? _resolve(AppState state) {
    final id = messageId.trim();
    if (id.isEmpty) return null;
    final dialog = state.selectedDialog ??
        state.dialogs.where((d) => d.id == dialogId).firstOrNull;
    if (dialog == null) return null;
    return dialog.messages.where((m) => m.id == id).firstOrNull ??
        dialog.messages.where((m) => m.hash.trim() == id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Consumer<AppState>(
      builder: (context, state, _) {
        final msg = _resolve(state);
        final lat = msg?.latitude ?? latitude;
        final lon = msg?.longitude ?? longitude;
        final adrs = ((msg?.address ?? address) ?? '').trim();
        final isLive = msg?.locationLive ?? live;

        return Material(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LiveGeoMap(
                latitude: lat,
                longitude: lon,
                followLive: isLive,
                zoom: 16,
                fallbackColor: p.bg3,
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: const Color(0xF01B1B1B),
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 2),
                  ),
                  elevation: 6,
                  shadowColor: Colors.black87,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              if (isLive)
                const Positioned(
                  left: 16,
                  top: 16,
                  child: _LiveBadge(),
                ),
              if (adrs.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC1B1B1B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        adrs,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC1B1B1B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me, size: 12, color: Color(0xFF9BFF4B)),
          SizedBox(width: 4),
          Text(
            'Live',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
