import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/forum_api_client.dart';
import '../../models/auth_models.dart';
import '../../services/auth_debug.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import 'sms_code_screen.dart';

/// Экран 2: QR-вход в стиле Telegram Desktop + кнопка SMS.
class QrLoginScreen extends StatefulWidget {
  final String? phone;
  final AuthCountry? country;

  const QrLoginScreen({
    super.key,
    this.phone,
    this.country,
  });

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
  final _api = ForumApiClient();
  String? _qrUrl;
  String? _error;
  bool _loadingQr = true;
  bool _smsLoading = false;
  bool _completing = false;
  bool _smsFlowActive = false;
  int _sessionGen = 0;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _api.onCheckQrAuth = _onCheckQr;
    _api.onDisconnected = _onWsDisconnected;
    _startQrSession();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _api.onCheckQrAuth = null;
    _api.onDisconnected = null;
    unawaited(_api.disconnect());
    _api.dispose();
    super.dispose();
  }

  void _onWsDisconnected() {
    if (!mounted || _completing || _smsFlowActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _completing || _smsFlowActive) return;
      setState(() => _error = 'Соединение закрыто. Обновляем QR…');
      _startQrSession();
    });
  }

  Future<void> _startQrSession() async {
    final gen = ++_sessionGen;
    _reconnectTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _loadingQr = true;
      _error = null;
      _qrUrl = null;
    });
    try {
      // Онбординг: WS без JWT.
      await _api.connect();
      if (!mounted || gen != _sessionGen || _smsFlowActive) return;
      final qr = await _api.requestQr();
      if (!mounted || gen != _sessionGen || _smsFlowActive) return;
      setState(() {
        _qrUrl = qr;
        _loadingQr = false;
        _error = null;
      });
    } on ForumApiException catch (e) {
      if (!mounted || gen != _sessionGen) return;
      setState(() {
        _error = e.message;
        _loadingQr = false;
      });
    } catch (e) {
      if (!mounted || gen != _sessionGen) return;
      // Переподключение само вызовет новый get_qr — не шумим StateError.
      final msg = e.toString();
      if (msg.contains('отключ') || msg.contains('отменено')) {
        setState(() => _loadingQr = true);
        return;
      }
      setState(() {
        _error = msg;
        _loadingQr = false;
      });
    }
  }

  Future<void> _onCheckQr(Map<String, dynamic> data) async {
    if (_completing || !mounted || _smsFlowActive) return;
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) return;
    setState(() => _completing = true);
    try {
      await context.read<AppState>().completeAuthentication(
            token: token,
            userId: data['id']?.toString(),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startSms() async {
    final phone = widget.phone?.trim() ?? '';
    final country = widget.country;
    if (phone.isEmpty || country == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала укажите номер телефона на предыдущем экране'),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _smsLoading = true;
      _smsFlowActive = true;
      _error = null;
    });
    _sessionGen++;
    _reconnectTimer?.cancel();
    try {
      await _api.disconnect();
    } catch (_) {}

    try {
      final result = await _api.requestSms(
        phone: phone,
        prefix: country.prefixWithPlus,
        prfxId: country.prfxId,
        test: AuthDebug.useTestSms,
      );
      if (!mounted) return;
      if (!AuthDebug.enabled &&
          result.hintText != null &&
          result.hintText!.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.hintText!)),
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmsCodeScreen(
            phone: phone,
            country: country,
            smsId: result.id,
            hintText: result.hintText,
            serverCode: AuthDebug.parseServerCode(result.hintText),
          ),
        ),
      );
    } on ForumApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _smsLoading = false;
          _smsFlowActive = false;
        });
        _startQrSession();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F4F5),
        elevation: 0,
        foregroundColor: const Color(0xFF0D0D0D),
        title: const Text('Вход в Forum'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final qrSize =
                            (constraints.maxHeight * 0.48).clamp(160.0, 280.0);
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _QrCard(
                                  size: qrSize,
                                  loading: _loadingQr || _completing,
                                  qrUrl: _qrUrl,
                                  onRefresh: _startQrSession,
                                ),
                                const SizedBox(height: 20),
                                const _StepRow(
                                  number: 1,
                                  text: 'Откройте приложение на телефоне',
                                ),
                                const SizedBox(height: 12),
                                const _StepRow(
                                  number: 2,
                                  text:
                                      'Откройте Настройки > Авторизация по QR-коду',
                                ),
                                const SizedBox(height: 12),
                                const _StepRow(
                                  number: 3,
                                  text:
                                      'Для подтверждения направьте камеру телефона на этот экран',
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFE5484D),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed:
                          (_smsLoading || _completing) ? null : _startSms,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        disabledBackgroundColor:
                            AppColors.purple.withValues(alpha: 0.4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _smsLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Авторизация по коду SMS',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final double size;
  final bool loading;
  final String? qrUrl;
  final VoidCallback onRefresh;

  const _QrCard({
    required this.size,
    required this.loading,
    required this.qrUrl,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final qrInner = (size - 40).clamp(120.0, 240.0);
    final logo = (size * 0.18).clamp(36.0, 52.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: loading
          ? const CircularProgressIndicator(color: AppColors.purple)
          : qrUrl == null
              ? TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить QR'),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: qrUrl!,
                      version: QrVersions.auto,
                      size: qrInner,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0D0D0D),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0D0D0D),
                      ),
                    ),
                    Container(
                      width: logo,
                      height: logo,
                      decoration: BoxDecoration(
                        color: AppColors.lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Icon(
                        Icons.key_rounded,
                        color: Colors.white,
                        size: logo * 0.5,
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.lime,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Color(0xFF0D0D0D),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Color(0xFF3F3F46),
            ),
          ),
        ),
      ],
    );
  }
}
