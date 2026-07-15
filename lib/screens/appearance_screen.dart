import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_config.dart';
import '../models/appearance_settings.dart';
import '../models/forum_database.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/cached_forum_image.dart';

/// Экран настроек оформления (Figma «Оформление»).
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late AppearanceSettings _draft;
  late AppearanceSettings _original;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _original = context.read<AppState>().appearance;
    _draft = _original;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final error = await state.saveAppearance(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    _saved = true;
    if (mounted) Navigator.of(context).pop();
  }

  void _update(AppearanceSettings next) {
    setState(() => _draft = next);
    context.read<AppState>().previewAppearance(next);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = context.palette;
    final db = state.database;
    final isDark = state.isDark;
    final profileName = state.profile?.name ?? 'Ваше имя';

    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_saved) {
          context.read<AppState>().previewAppearance(_original);
        }
      },
      child: Scaffold(
        backgroundColor: p.bg1,
        appBar: AppBar(
          backgroundColor: p.bg1,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: p.text1, size: 20),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: Text(
            'Оформление',
            style: TextStyle(
              color: p.text1,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.purple,
                      ),
                    )
                  : Text(
                      'Готово',
                      style: TextStyle(
                        color: p.purple,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionLabel('LIQUID GLASS'),
            _LiquidGlassToggle(
              value: _draft.liquidGlass,
              onChanged: (v) => _update(_draft.copyWith(liquidGlass: v)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ПРОЗРАЧНОСТЬ'),
            _TransparencySlider(
              value: _draft.transparency,
              accent: p.lime,
              onChanged: (v) => _update(_draft.copyWith(transparency: v)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ТЕМА ОФОРМЛЕНИЯ'),
            _ThemeCard(
              selected: _draft.theme,
              onChanged: (theme) => _update(_draft.copyWith(theme: theme)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ИНДИВИДУАЛЬНЫЕ НАСТРОЙКИ ТЕМЫ'),
            _PreviewCard(
              name: profileName,
              draft: _draft,
              database: db,
              isDark: isDark,
              palette: p,
            ),
            const SizedBox(height: 24),
            _SectionLabel('ЦВЕТА ПРИЛОЖЕНИЯ'),
            _AppColorPicker(
              colors: db.appColors,
              selectedId: _draft.appColorId,
              isDark: isDark,
              onSelected: (id) => _update(_draft.copyWith(appColorId: id)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ЦВЕТ ИМЕНИ'),
            _NameColorPicker(
              colors: db.nameColors,
              selectedId: _draft.nameColorId,
              isDark: isDark,
              onSelected: (id) => _update(_draft.copyWith(nameColorId: id)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ЦВЕТ АВАТАРА'),
            _AvatarColorPicker(
              colors: db.avatarColors,
              selectedId: _draft.avatarColorId,
              name: profileName,
              isDark: isDark,
              onSelected: (id) => _update(_draft.copyWith(avatarColorId: id)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('ФОН В ЧАТАХ'),
            _BackgroundPicker(
              backgrounds: db.backgroundsFor(isDark),
              selectedUrl: _draft.bgImg,
              onSelected: (url) => _update(_draft.copyWith(bgImg: url)),
            ),
            const SizedBox(height: 24),
            _SectionLabel('РАЗМЕР ТЕКСТА'),
            _TextSizeSlider(
              value: _draft.textSizeOffset,
              accent: p.lime,
              onChanged: (v) => _update(_draft.copyWith(textSizeOffset: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: p.text3,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppearanceTheme selected;
  final ValueChanged<AppearanceTheme> onChanged;

  const _ThemeCard({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _ThemeOption(
            title: 'Системная',
            subtitle: 'По умолчанию',
            selected: selected == AppearanceTheme.system,
            onTap: () => onChanged(AppearanceTheme.system),
          ),
          Divider(height: 1, color: p.border1),
          _ThemeOption(
            title: 'Тёмная',
            subtitle: 'Экономит заряд аккумулятора',
            selected: selected == AppearanceTheme.dark,
            onTap: () => onChanged(AppearanceTheme.dark),
          ),
          Divider(height: 1, color: p.border1),
          _ThemeOption(
            title: 'Светлая',
            subtitle: 'В моде при любой погоде',
            selected: selected == AppearanceTheme.light,
            onTap: () => onChanged(AppearanceTheme.light),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: p.text2, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? p.lime : p.text3,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String name;
  final AppearanceSettings draft;
  final ForumDatabase database;
  final bool isDark;
  final ForumPalette palette;

  const _PreviewCard({
    required this.name,
    required this.draft,
    required this.database,
    required this.isDark,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final app = database.appColorById(draft.appColorId);
    final target = app == null
        ? palette.purple
        : AppColors.parseHex(isDark ? app.d1 : app.l1);
    final nameEntry = database.nameColorById(draft.nameColorId);
    final nameColor = nameEntry == null
        ? palette.purple
        : AppColors.parseHex(isDark ? nameEntry.d : nameEntry.l);
    final ava = database.avatarById(draft.avatarColorId);
    final avaHex = ava?.hexForDark(isDark) ?? const ['904FFF', '5B36C9'];

    final bgUrl = draft.bgImg.trim().isEmpty
        ? null
        : (draft.bgImg.startsWith('http')
            ? draft.bgImg
            : ApiConfig.fileUrl(
                '',
                draft.bgImg.startsWith('/') ? draft.bgImg.substring(1) : draft.bgImg,
              ));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bgUrl != null)
              CachedForumImage(url: bgUrl, fit: BoxFit.cover)
            else
              Container(color: palette.bg1),
            Container(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.08)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AvatarWidget(
                        name: name,
                        avatarColor: avaHex,
                        size: 40,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: nameColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _PreviewBubble(
                      text: 'Отображение в группе',
                      color: palette.bg3,
                      textColor: palette.text1,
                      liquidGlass: draft.liquidGlass,
                      opacity: draft.panelOpacity,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _PreviewBubble(
                      text: 'Цвет своего сообщения',
                      color: target,
                      textColor: Colors.white,
                      liquidGlass: draft.liquidGlass,
                      opacity: draft.panelOpacity,
                    ),
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

class _PreviewBubble extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final bool liquidGlass;
  final double opacity;

  const _PreviewBubble({
    required this.text,
    required this.color,
    required this.textColor,
    this.liquidGlass = false,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    final fill = color.withValues(alpha: liquidGlass ? opacity : 1.0);
    Widget bubble = Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontSize: 14),
      ),
    );

    if (liquidGlass) {
      bubble = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: bubble,
        ),
      );
    }

    return bubble;
  }
}

class _LiquidGlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _LiquidGlassToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.bg2,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        title: Text(
          'Liquid Glass',
          style: TextStyle(
            color: p.text1,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        value: value,
        activeTrackColor: p.lime.withValues(alpha: 0.45),
        activeThumbColor: p.lime,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _TransparencySlider extends StatelessWidget {
  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;

  const _TransparencySlider({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _CompactIconButton(
            onPressed: value > AppearanceSettings.minTransparency
                ? () => onChanged(value - 5)
                : null,
            icon: Icons.remove,
            color: p.text2,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: p.purple,
                inactiveTrackColor: p.border1,
                thumbColor: p.purple,
                overlayColor: p.purple.withValues(alpha: 0.12),
              ),
              child: Slider(
                min: AppearanceSettings.minTransparency.toDouble(),
                max: AppearanceSettings.maxTransparency.toDouble(),
                divisions: 20,
                value: value.toDouble(),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: p.bg3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$value%',
              style: TextStyle(color: accent, fontSize: 13),
            ),
          ),
          _CompactIconButton(
            onPressed: value < AppearanceSettings.maxTransparency
                ? () => onChanged(value + 5)
                : null,
            icon: Icons.add,
            color: p.text2,
          ),
        ],
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;

  const _CompactIconButton({
    required this.onPressed,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, color: color),
    );
  }
}

class _AppColorPicker extends StatelessWidget {
  final List<AppColorPalette> colors;
  final int selectedId;
  final bool isDark;
  final ValueChanged<int> onSelected;

  const _AppColorPicker({
    required this.colors,
    required this.selectedId,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = colors[index];
          final c1 = AppColors.parseHex(isDark ? item.d1 : item.l1);
          final c2 = AppColors.parseHex(isDark ? item.d2 : item.l2);
          final selected = item.id == selectedId;
          return GestureDetector(
            onTap: () => onSelected(item.id),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [c1, c2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: selected
                    ? Border.all(color: context.palette.lime, width: 2.5)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NameColorPicker extends StatelessWidget {
  final List<NameColorPalette> colors;
  final int selectedId;
  final bool isDark;
  final ValueChanged<int> onSelected;

  const _NameColorPicker({
    required this.colors,
    required this.selectedId,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = colors[index];
          final color = AppColors.parseHex(isDark ? item.d : item.l);
          final selected = item.id == selectedId;
          return GestureDetector(
            onTap: () => onSelected(item.id),
            child: Container(
              width: 44,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: context.palette.lime, width: 2)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvatarColorPicker extends StatelessWidget {
  final List<AvatarColorPalette> colors;
  final int selectedId;
  final String name;
  final bool isDark;
  final ValueChanged<int> onSelected;

  const _AvatarColorPicker({
    required this.colors,
    required this.selectedId,
    required this.name,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = colors[index];
          final selected = item.id == selectedId;
          return GestureDetector(
            onTap: () => onSelected(item.id),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: context.palette.lime, width: 2.5)
                    : null,
              ),
              child: AvatarWidget(
                name: name,
                avatarColor: item.hexForDark(isDark),
                size: 46,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackgroundPicker extends StatelessWidget {
  final List<ChatBackgroundOption> backgrounds;
  final String selectedUrl;
  final ValueChanged<String> onSelected;

  const _BackgroundPicker({
    required this.backgrounds,
    required this.selectedUrl,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: backgrounds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final bg = backgrounds[index];
          final selected = bg.url.trim() == selectedUrl.trim();
          final url = bg.isEmpty
              ? null
              : (bg.url.startsWith('http')
                  ? bg.url
                  : ApiConfig.fileUrl(
                      '',
                      bg.url.startsWith('/') ? bg.url.substring(1) : bg.url,
                    ));

          return GestureDetector(
            onTap: () => onSelected(bg.url),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: p.bg3,
                border: selected
                    ? Border.all(color: p.lime, width: 2.5)
                    : Border.all(color: p.border1),
              ),
              clipBehavior: Clip.antiAlias,
              child: bg.isEmpty
                  ? Icon(Icons.block, color: p.text3, size: 28)
                  : (url == null
                      ? const SizedBox.shrink()
                      : CachedForumImage(url: url, fit: BoxFit.cover)),
            ),
          );
        },
      ),
    );
  }
}

class _TextSizeSlider extends StatelessWidget {
  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;

  const _TextSizeSlider({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _CompactIconButton(
            onPressed: value > AppearanceSettings.minTextSizeOffset
                ? () => onChanged(value - 1)
                : null,
            icon: Icons.remove,
            color: p.text2,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                inactiveTrackColor: p.border1,
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                min: AppearanceSettings.minTextSizeOffset.toDouble(),
                max: AppearanceSettings.maxTextSizeOffset.toDouble(),
                divisions: AppearanceSettings.maxTextSizeOffset -
                    AppearanceSettings.minTextSizeOffset,
                value: value.toDouble(),
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
          if (value != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: p.bg3,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value > 0 ? '+$value' : '$value',
                style: TextStyle(color: p.text1, fontSize: 13),
              ),
            ),
          _CompactIconButton(
            onPressed: value < AppearanceSettings.maxTextSizeOffset
                ? () => onChanged(value + 1)
                : null,
            icon: Icons.add,
            color: p.text2,
          ),
        ],
      ),
    );
  }
}
