import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/device_session.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// «Подключенные устройства» — как в Forum_ios `ConnectedDevicesViewController`:
/// секции «Это устройство» / «Активные устройства», device_del / device_del_all.
class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  bool _loading = true;
  String? _error;
  DeviceSession? _thisDevice;
  List<DeviceSession> _otherDevices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    try {
      final currentUid = await state.currentDeviceUid();
      final devices = await state.loadDevices();
      if (!mounted) return;
      final current = devices
          .where((d) => d.uid == currentUid)
          .cast<DeviceSession?>()
          .firstWhere((_) => true, orElse: () => null);
      setState(() {
        _thisDevice = current ?? (devices.isNotEmpty ? devices.first : null);
        final keepUid = _thisDevice?.uid;
        _otherDevices =
            devices.where((d) => d.uid != keepUid).toList(growable: false);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _terminateAllOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить все другие сеансы?'),
        content: const Text('Выйти на всех устройствах, кроме этого.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Завершить',
              style: TextStyle(color: Color(0xFFE53935)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().terminateAllOtherSessions();
      if (!mounted) return;
      setState(() => _otherDevices = const []);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось завершить сеансы: $e')),
      );
    }
  }

  Future<void> _openDetail(DeviceSession device) async {
    final disconnected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceDetailSheet(device: device),
    );
    if (disconnected == true && mounted) {
      setState(() {
        _otherDevices =
            _otherDevices.where((d) => d.uid != device.uid).toList();
      });
      await _load();
    }
  }

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
          'Подключенные устройства',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : () {
              setState(() => _loading = true);
              _load();
            },
            icon: Icon(Icons.refresh_rounded, color: p.purple),
          ),
        ],
      ),
      body: _buildBody(p, cardBg, separator),
    );
  }

  Widget _buildBody(ForumPalette p, Color cardBg, Color separator) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Не удалось загрузить устройства',
                style: TextStyle(color: p.text1, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text3, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_thisDevice != null) ...[
            const _SectionHeader(title: 'ЭТО УСТРОЙСТВО'),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _DeviceRow(
                    device: _thisDevice!,
                    onTap: () => _openDetail(_thisDevice!),
                  ),
                  if (_otherDevices.isNotEmpty) ...[
                    Divider(height: 0.5, thickness: 0.5, color: separator),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _terminateAllOthers,
                        child: const SizedBox(
                          height: 46,
                          child: Center(
                            child: Text(
                              'Завершить все другие сеансы',
                              style: TextStyle(
                                color: Color(0xFFE53935),
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_otherDevices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'Выйти на всех устройствах, кроме этого.',
                  style: TextStyle(color: p.text3, fontSize: 12),
                ),
              ),
          ],
          if (_otherDevices.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'АКТИВНЫЕ УСТРОЙСТВА'),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _otherDevices.length; i++) ...[
                    _DeviceRow(
                      device: _otherDevices[i],
                      onTap: () => _openDetail(_otherDevices[i]),
                    ),
                    if (i < _otherDevices.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 56),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: separator,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: p.text3,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

IconData deviceIcon(DeviceSession device) {
  final lower = device.os.toLowerCase();
  if (lower.contains('mac')) return Icons.laptop_mac_rounded;
  if (lower.contains('ipad')) return Icons.tablet_mac_rounded;
  if (lower.contains('ios') || lower.contains('iphone')) {
    return Icons.phone_iphone_rounded;
  }
  if (lower.contains('android')) return Icons.smartphone_rounded;
  if (lower.contains('web') ||
      lower.contains('safari') ||
      lower.contains('chrome')) {
    return Icons.language_rounded;
  }
  return Icons.desktop_windows_rounded;
}

class _DeviceRow extends StatelessWidget {
  final DeviceSession device;
  final VoidCallback onTap;

  const _DeviceRow({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const green = Color(0xFF3FB950);
    final online = device.online;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: p.purple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      deviceIcon(device),
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      device.titleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (online) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    device.trailingStatusText,
                    style: TextStyle(
                      color: online ? green : p.text3,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (device.subtitleText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Text(
                    device.subtitleText,
                    style: TextStyle(color: p.text2, fontSize: 13),
                  ),
                ),
              ],
              if (device.locationText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: Text(
                    device.locationText,
                    style: TextStyle(color: p.text3, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Деталка устройства — как `DeviceSessionDetailViewController`:
/// карточка + «Отключить устройство» (для чужих сеансов).
class _DeviceDetailSheet extends StatefulWidget {
  final DeviceSession device;

  const _DeviceDetailSheet({required this.device});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  bool _busy = false;

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить устройство?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Да',
              style: TextStyle(color: Color(0xFFE53935)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().terminateDevice(widget.device.uid);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отключить устройство: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final cardBg = state.isDark ? p.bg2 : Colors.white;
    final device = widget.device;
    final isCurrent = device.uid == state.deviceUid;
    const green = Color(0xFF3FB950);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: pageBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: p.purple),
                ),
                Expanded(
                  child: Text(
                    'Устройство',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.text1,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: p.purple,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          deviceIcon(device),
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          device.titleText,
                          style: TextStyle(
                            color: p.text1,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        device.trailingStatusText,
                        style: TextStyle(
                          color: device.online && isCurrent ? green : p.text3,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (device.subtitleText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Text(
                        device.subtitleText,
                        style: TextStyle(color: p.text2, fontSize: 13),
                      ),
                    ),
                  ],
                  if (device.locationText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Text(
                        device.locationText,
                        style: TextStyle(color: p.text3, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCurrent) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: Material(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _busy ? null : _disconnect,
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Отключить устройство',
                              style: TextStyle(
                                color: Color(0xFFE53935),
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
