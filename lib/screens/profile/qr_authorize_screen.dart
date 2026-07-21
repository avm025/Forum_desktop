import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// «Авторизовать по QR-коду» — как `QRCodeScannerViewController` в Forum_ios,
/// но для десктопа: вместо камеры — вставка ссылки из QR другого устройства.
/// Отправляет тот же WS `check_qr` c `data.qr`.
class QrAuthorizeScreen extends StatefulWidget {
  const QrAuthorizeScreen({super.key});

  @override
  State<QrAuthorizeScreen> createState() => _QrAuthorizeScreenState();
}

class _QrAuthorizeScreenState extends State<QrAuthorizeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<void> _authorize() async {
    final qr = _controller.text.trim();
    if (qr.isEmpty) {
      setState(() => _error = 'Вставьте ссылку из QR-кода');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().authorizeByQr(qr);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Устройство авторизовано')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось подтвердить QR-код: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final pageBg = state.isDark ? p.bg1 : const Color(0xFFF4F5F7);
    final cardBg = state.isDark ? p.bg2 : Colors.white;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: p.text1,
        centerTitle: true,
        title: Text(
          'Авторизовать по QR-коду',
          style: TextStyle(
            color: p.text1,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 72,
                color: p.purple,
              ),
              const SizedBox(height: 16),
              Text(
                'Откройте QR-код на экране входа другого устройства '
                'и вставьте сюда ссылку из него',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.text2, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_busy,
                        style: TextStyle(color: p.text1, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'https://4um.me/?qr=…',
                          hintStyle: TextStyle(color: p.text3, fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _authorize(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Вставить из буфера',
                      onPressed: _busy ? null : _pasteFromClipboard,
                      icon: Icon(Icons.content_paste_rounded,
                          size: 20, color: p.purple),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE53935),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _busy ? null : _authorize,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Авторизовать',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
