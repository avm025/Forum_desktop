import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/auth_models.dart';
import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import 'qr_login_screen.dart';

/// Экран 1: ввод номера телефона.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _focus = FocusNode();
  AuthCountry _country = AuthCountry.russia;
  List<AuthCountry> _countries = const [AuthCountry.russia];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCountries());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    final state = context.read<AppState>();
    final list = await state.loadAuthCountries();
    if (!mounted) return;
    setState(() {
      _countries = list;
      _country = list.firstWhere(
        (c) => c.iso == 'RU',
        orElse: () => list.first,
      );
    });
  }

  String get _digitsOnly =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '');

  String get _fullPhone {
    final prefix = _country.prefixWithPlus;
    return '$prefix$_digitsOnly';
  }

  bool get _isValid {
    final len = _digitsOnly.length;
    final expected = _country.length > 0 ? _country.length : 10;
    return len == expected || (len >= 10 && len <= 15);
  }

  Future<void> _continue() async {
    setState(() => _error = null);
    if (!_isValid) {
      setState(() => _error = 'Введите корректный номер телефона');
      return;
    }

    setState(() => _loading = true);
    try {
      // Дальше — QR (как в Telegram Desktop); SMS — с кнопки на QR-экране.
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrLoginScreen(
            phone: _fullPhone,
            country: _country,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<AuthCountry>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _countries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final c = _countries[index];
              return ListTile(
                title: Text(c.name),
                trailing: Text(
                  c.prefixWithPlus,
                  style: const TextStyle(
                    color: AppColors.purple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        );
      },
    );
    if (selected != null) setState(() => _country = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  const Text(
                    'Ваш номер телефона',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D0D0D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Укажите номер, к которому будет привязан аккаунт Forum. '
                    'Затем можно войти по QR с телефона или получить SMS-код.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: _pickCountry,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _country.prefixWithPlus,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0D0D0D),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.expand_more,
                                  color: Color(0xFF666666),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: const Color(0xFFE4E4E7),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            focusNode: _focus,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(15),
                            ],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0D0D0D),
                            ),
                            decoration: const InputDecoration(
                              hintText: '999 123 45 67',
                              hintStyle: TextStyle(color: Color(0xFFAAAAAA)),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _continue(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFE5484D),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _continue,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        disabledBackgroundColor:
                            AppColors.purple.withValues(alpha: 0.4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Продолжить',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () async {
                            setState(() => _loading = true);
                            try {
                              if (!mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const QrLoginScreen(),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _loading = false);
                              }
                            }
                          },
                    child: const Text(
                      'Войти только по QR-коду',
                      style: TextStyle(
                        color: AppColors.purple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
