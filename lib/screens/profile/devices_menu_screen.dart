import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'connected_devices_screen.dart';
import 'qr_authorize_screen.dart';

/// «Устройства» — как в Forum_ios `DevicesMenuViewController`:
/// авторизация по QR + подключенные устройства.
class DevicesMenuScreen extends StatelessWidget {
  const DevicesMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final separator = state.isDark ? p.border1 : const Color(0xFFE9E9E9);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: p.text1,
        centerTitle: true,
        title: Text(
          'Устройства',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _MenuRow(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Авторизовать по QR-коду',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const QrAuthorizeScreen(),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child:
                      Divider(height: 0.5, thickness: 0.5, color: separator),
                ),
                _MenuRow(
                  icon: Icons.devices_rounded,
                  label: 'Подключенные устройства',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConnectedDevicesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: p.lime, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: p.text1, fontSize: 15),
                  ),
                ),
                Icon(Icons.chevron_right, color: p.purple, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
