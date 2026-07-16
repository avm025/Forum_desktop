import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/forum_api_client.dart';
import '../../models/auth_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';

/// Экран 3: ввод SMS-кода + ожидание JWT через HTTP check_code.
class SmsCodeScreen extends StatefulWidget {
  final String phone;
  final AuthCountry country;
  final String smsId;
  final String? hintText;

  const SmsCodeScreen({
    super.key,
    required this.phone,
    required this.country,
    required this.smsId,
    this.hintText,
  });

  @override
  State<SmsCodeScreen> createState() => _SmsCodeScreenState();
}

class _SmsCodeScreenState extends State<SmsCodeScreen> {
  final _api = ForumApiClient();
  final _controllers =
      List.generate(5, (_) => TextEditingController());
  final _focusNodes = List.generate(5, (_) => FocusNode());

  late String _smsId;
  String? _error;
  bool _submitting = false;
  bool _resending = false;
  int _cooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _smsId = widget.smsId;
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _api.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _submitIfReady() async {
    if (_code.length != 5 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _api.checkSmsCode(smsId: _smsId, code: _code);
      if (!mounted) return;
      await context.read<AppState>().completeAuthentication(
            token: result.token,
            userId: result.userId,
            phone: result.phone.isNotEmpty ? result.phone : widget.phone,
          );
    } on ForumApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final result = await _api.requestSms(
        phone: widget.phone,
        prefix: widget.country.prefixWithPlus,
        prfxId: widget.country.prfxId,
        test: false,
      );
      if (!mounted) return;
      _smsId = result.id;
      if (result.hintText != null && result.hintText!.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.hintText!)),
        );
      }
      _startCooldown();
    } on ForumApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // paste
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < 5; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final focusAt = digits.length.clamp(0, 4);
      _focusNodes[focusAt].requestFocus();
      _submitIfReady();
      setState(() {});
      return;
    }

    if (value.isNotEmpty && index < 4) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _error = null);
    _submitIfReady();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F4F5),
        elevation: 0,
        foregroundColor: const Color(0xFF0D0D0D),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Код из SMS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D0D0D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Мы отправили код на ${widget.phone}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF666666),
                    ),
                  ),
                  if (widget.hintText != null &&
                      widget.hintText!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.hintText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.purple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (i) {
                      return SizedBox(
                        width: 52,
                        height: 60,
                        child: TextField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0D0D0D),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.zero,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E4E7),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.purple,
                                width: 1.6,
                              ),
                            ),
                          ),
                          onChanged: (v) => _onDigitChanged(i, v),
                        ),
                      );
                    }),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE5484D),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_submitting)
                    const Center(
                      child: CircularProgressIndicator(color: AppColors.purple),
                    )
                  else
                    TextButton(
                      onPressed: _cooldown > 0 || _resending ? null : _resend,
                      child: Text(
                        _resending
                            ? 'Отправка…'
                            : _cooldown > 0
                                ? 'Отправить код ещё раз через $_cooldown с'
                                : 'Отправить код ещё раз',
                        style: TextStyle(
                          color: _cooldown > 0
                              ? const Color(0xFF999999)
                              : AppColors.purple,
                          fontWeight: FontWeight.w600,
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
