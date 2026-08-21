import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chat_type.dart';
import '../../models/dialogs_list_view_model.dart';
import '../../models/dlg_info_member.dart';
import '../../models/media_file.dart';
import '../../models/message_view_model.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/reaction_utils.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/cached_forum_image.dart';
import '../../widgets/fullscreen_image_view.dart';

/// Профиль собеседника / группы — порт iOS `AnotherProfileViewController`.
class PeerProfileScreen extends StatefulWidget {
  final String dialogId;

  const PeerProfileScreen({super.key, required this.dialogId});

  static Future<void> open(BuildContext context, DialogsListViewModel dialog) {
    final id = dialog.id?.trim() ?? '';
    if (id.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PeerProfileScreen(dialogId: id),
      ),
    );
  }

  @override
  State<PeerProfileScreen> createState() => _PeerProfileScreenState();
}

enum _MediaTab { members, photos, videos, files, voice, links }

class _PeerProfileScreenState extends State<PeerProfileScreen> {
  bool _loadingInfo = true;
  bool _muted = false;
  List<DlgInfoMember> _members = const [];
  String _phone = '';
  String _nick = '';
  String _about = '';
  _MediaTab? _tab;

  @override
  void initState() {
    super.initState();
    final dialog = _dialogOf(context.read<AppState>());
    _muted = dialog?.chatMuted ?? false;
    _phone = dialog?.phone?.trim() ?? '';
    _nick = dialog?.groupAditionalInfo?.nick?.trim() ?? '';
    _about = dialog?.groupAditionalInfo?.desc?.trim() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInfo());
  }

  DialogsListViewModel? _dialogOf(AppState state) {
    for (final d in state.dialogs) {
      if (AppState.dlgIdsEqual(d.id, widget.dialogId)) return d;
    }
    return state.selectedDialog;
  }

  Future<void> _loadInfo() async {
    final state = context.read<AppState>();
    final dialog = _dialogOf(state);
    if (dialog == null || dialog.isNewContactWithoutDialog) {
      if (mounted) setState(() => _loadingInfo = false);
      return;
    }
    try {
      final info = await state.fetchDlgInfo(widget.dialogId);
      if (!mounted) return;
      final peerId = dialog.usr_id?.trim() ?? '';
      String phone = _phone;
      String nick = _nick;
      if (!dialog.isGrp && peerId.isNotEmpty) {
        DlgInfoMember? peer;
        for (final u in info.users) {
          if (ReactionUtils.sameUserId(u.id, peerId)) {
            peer = u;
            break;
          }
        }
        if (peer != null) {
          if (peer.phone.trim().isNotEmpty) phone = peer.phone.trim();
          if (peer.nick.trim().isNotEmpty) nick = peer.nick.trim();
        }
      } else if (dialog.isGrp) {
        if ((info.groupNick ?? '').trim().isNotEmpty) {
          nick = info.groupNick!.trim();
        } else if (_nick.isEmpty) {
          nick = dialog.groupAditionalInfo?.nick?.trim() ?? '';
        }
      }
      final about = (info.about ?? info.groupDesc ?? _about).trim();
      setState(() {
        _members = info.users;
        _phone = phone;
        _nick = nick;
        _about = about;
        _loadingInfo = false;
        _tab ??= _defaultTab(dialog);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingInfo = false;
          _tab ??= _defaultTab(dialog);
        });
      }
    }
  }

  _MediaTab? _defaultTab(DialogsListViewModel dialog) {
    final tabs = _availableTabs(dialog);
    return tabs.isEmpty ? null : tabs.first;
  }

  List<_MediaTab> _availableTabs(DialogsListViewModel dialog) {
    final media = _collectMedia(dialog.messages);
    final tabs = <_MediaTab>[];
    if (dialog.isGrp && _members.isNotEmpty) tabs.add(_MediaTab.members);
    if (media.photos.isNotEmpty) tabs.add(_MediaTab.photos);
    if (media.videos.isNotEmpty) tabs.add(_MediaTab.videos);
    if (media.files.isNotEmpty) tabs.add(_MediaTab.files);
    if (media.voices.isNotEmpty) tabs.add(_MediaTab.voice);
    if (media.links.isNotEmpty) tabs.add(_MediaTab.links);
    return tabs;
  }

  _MediaBuckets _collectMedia(List<MessageViewModel> messages) {
    final photos = <MediaFile>[];
    final videos = <MediaFile>[];
    final files = <_FileRow>[];
    final voices = <MessageViewModel>[];
    final links = <_LinkRow>[];

    for (final m in messages) {
      final t = m.type.toLowerCase();
      if (t == 'voice' || m.isVoice) {
        voices.add(m);
        continue;
      }
      if (t == 'file' || m.isFile) {
        files.add(_FileRow(
          title: (m.fileTitle ?? m.text).trim().isEmpty
              ? 'Файл'
              : (m.fileTitle ?? m.text).trim(),
          subtitle: [
            if ((m.fileSize ?? '').isNotEmpty) m.fileSize!,
            if ((m.fileFormat ?? '').isNotEmpty) m.fileFormat!,
          ].join(' · '),
          url: m.url,
        ));
        continue;
      }
      if (t == 'text' || t == 'msg' || t.isEmpty) {
        final text = m.text.trim().isNotEmpty ? m.text.trim() : m.body.trim();
        if (_isHttpUrl(text)) {
          links.add(_LinkRow(
            link: text,
            name: m.fr_name,
            time: m.dtshow.isNotEmpty ? m.dtshow : m.dttmcr,
          ));
        }
      }
      if (m.files.isNotEmpty) {
        for (final f in m.files) {
          if (f.isVideo) {
            videos.add(f);
          } else if (f.url.isNotEmpty || (f.bytes?.isNotEmpty ?? false)) {
            photos.add(f);
          }
        }
        continue;
      }
      if (t == 'video') {
        videos.add(MediaFile(url: m.url, preview: m.preview, kind: 'mp4'));
      } else if (t == 'image' || t == 'img' || t == 'photo' || t == 'media') {
        if (m.url.isNotEmpty) {
          photos.add(MediaFile(url: m.url, preview: m.preview));
        }
      }
    }
    return _MediaBuckets(
      photos: photos,
      videos: videos,
      files: files,
      voices: voices,
      links: links,
    );
  }

  static bool _isHttpUrl(String text) {
    final t = text.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    var d = digits;
    if (d.length == 11 && (d.startsWith('7') || d.startsWith('8'))) {
      d = d.substring(1);
    }
    if (d.length == 10) {
      return '+7 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
    }
    return raw.startsWith('+') ? raw : '+$raw';
  }

  String _subtitle(DialogsListViewModel dialog) {
    if (dialog.fav) return 'избранное';
    if (!dialog.isGrp && dialog.chatType != ChatType.groupChat) {
      return dialog.online ? 'в сети' : 'был(а) недавно';
    }
    final total = _members.isNotEmpty ? _members.length : 0;
    final online = _members.where((m) => m.online).length;
    final word = switch (total) {
      1 => 'участник',
      2 || 3 || 4 => 'участника',
      _ => 'участников',
    };
    if (total == 0) return 'группа';
    return '$total $word, $online онлайн';
  }

  Future<void> _copyNick() async {
    final nick = _nick.trim();
    if (nick.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: nick.replaceFirst('@', '')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Уникальное имя скопировано')),
    );
  }

  Future<void> _callPhone() async {
    final formatted = _formatPhone(_phone);
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: '+$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showMoreMenu(DialogsListViewModel dialog) {
    final isGrp = dialog.isGrp || dialog.chatType == ChatType.groupChat;
    final items = isGrp
        ? const [
            'Добавить в группу',
            'Удалить переписку',
            'Пожаловаться',
            'Покинуть группу',
            'Удалить группу',
          ]
        : const [
            'Отправить контакт',
            'Удалить переписку',
            'Пожаловаться',
            'Заблокировать',
          ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        final p = ctx.palette;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++)
                ListTile(
                  title: Text(
                    items[i],
                    style: TextStyle(
                      color: i == items.length - 1
                          ? const Color(0xFFFF453A)
                          : p.text1,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onMoreAction(dialog, items[i]);
                  },
                ),
              ListTile(
                title: Text('Отмена', style: TextStyle(color: p.text2)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onMoreAction(DialogsListViewModel dialog, String action) async {
    final destructive = action == 'Заблокировать' ||
        action == 'Удалить группу' ||
        action == 'Покинуть группу' ||
        action == 'Удалить переписку';
    if (!destructive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action — скоро')),
      );
      return;
    }

    String message;
    if (action == 'Заблокировать') {
      message =
          'Запретить ${dialog.chatName} писать Вам сообщения и звонить?';
    } else if (action == 'Удалить переписку') {
      message = 'Удалить переписку?';
    } else if (action == 'Покинуть группу') {
      message =
          'Групповой чат ${dialog.chatName} пропадет из списка диалогов. Доступ к переписке будет утерян.';
    } else {
      message = 'Удалить группу «${dialog.chatName}»?';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = ctx.palette;
        return AlertDialog(
          backgroundColor: p.bg2,
          title: Text(action, style: TextStyle(color: p.text1)),
          content: Text(message, style: TextStyle(color: p.text2)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: p.text2)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                action,
                style: const TextStyle(color: Color(0xFFFF453A)),
              ),
            ),
          ],
        );
      },
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action — скоро')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dialog = _dialogOf(state);
    final p = context.palette;
    if (dialog == null) {
      return Scaffold(
        backgroundColor: p.bg1,
        appBar: AppBar(
          backgroundColor: p.bg1,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: p.text1),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(
          child: Text('Диалог не найден', style: TextStyle(color: p.text2)),
        ),
      );
    }

    final isGrp = dialog.isGrp || dialog.chatType == ChatType.groupChat;
    final media = _collectMedia(dialog.messages);
    final tabs = _availableTabs(dialog);
    final activeTab = _tab != null && tabs.contains(_tab) ? _tab : (tabs.isEmpty ? null : tabs.first);

    return Scaffold(
      backgroundColor: p.bg1,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _HeroHeader(dialog: dialog)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      Text(
                        dialog.chatName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.text1,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(dialog),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: p.text2.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ActionStrip(
                        fav: dialog.fav,
                        isGroup: isGrp,
                        muted: _muted,
                        onChat: () => Navigator.of(context).maybePop(),
                        onSearch: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Поиск — скоро')),
                          );
                        },
                        onMute: () => setState(() => _muted = !_muted),
                        onLeave: () => _onMoreAction(dialog, 'Покинуть группу'),
                        onMore: () => _showMoreMenu(dialog),
                        onFavSearch: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Поиск — скоро')),
                          );
                        },
                        onFavClear: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Очистить — скоро')),
                          );
                        },
                      ),
                      if (!dialog.fav) ...[
                        const SizedBox(height: 12),
                        _InfoCard(
                          phone: isGrp ? '' : _formatPhone(_phone),
                          nick: _nick,
                          about: _about,
                          isGroup: isGrp,
                          onPhone: _callPhone,
                          onNick: isGrp ? null : _copyNick,
                        ),
                      ],
                      if (isGrp) ...[
                        const SizedBox(height: 12),
                        _AddMemberButton(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Добавить участника — скоро'),
                              ),
                            );
                          },
                        ),
                      ],
                      if (_loadingInfo) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.lime,
                          ),
                        ),
                      ],
                      if (tabs.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _TabStrip(
                          tabs: tabs,
                          active: activeTab!,
                          onSelect: (t) => setState(() => _tab = t),
                        ),
                        const SizedBox(height: 12),
                        _TabBody(
                          tab: activeTab,
                          members: _members,
                          media: media,
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  _ChromeButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (!dialog.fav)
                    _ChromeButton(
                      icon: Icons.edit_outlined,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isGrp
                                  ? 'Настройки группы — скоро'
                                  : 'Редактирование — скоро',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final DialogsListViewModel dialog;

  const _HeroHeader({required this.dialog});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasAva = dialog.avatar.trim().isNotEmpty;
    return SizedBox(
      height: 285,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAva)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CachedForumImage(
                url: dialog.avatar,
                fit: BoxFit.cover,
              ),
            )
          else
            ColoredBox(color: p.bg3),
          ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
          Center(
            child: AvatarWidget(
              name: dialog.chatName,
              avatarUrl: dialog.avatar,
              avatarColor: dialog.avatarColor,
              colAvaId: dialog.colAvaId,
              online: dialog.online,
              size: 112,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ChromeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _ActionStrip extends StatelessWidget {
  final bool fav;
  final bool isGroup;
  final bool muted;
  final VoidCallback onChat;
  final VoidCallback onSearch;
  final VoidCallback onMute;
  final VoidCallback onLeave;
  final VoidCallback onMore;
  final VoidCallback onFavSearch;
  final VoidCallback onFavClear;

  const _ActionStrip({
    required this.fav,
    required this.isGroup,
    required this.muted,
    required this.onChat,
    required this.onSearch,
    required this.onMute,
    required this.onLeave,
    required this.onMore,
    required this.onFavSearch,
    required this.onFavClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final actions = <_ActionItem>[];
    if (fav) {
      actions.addAll([
        _ActionItem(Icons.search_rounded, 'Поиск', onFavSearch),
        _ActionItem(Icons.delete_outline_rounded, 'Очистить', onFavClear),
      ]);
    } else if (isGroup) {
      actions.addAll([
        _ActionItem(Icons.search_rounded, 'Поиск', onSearch),
        _ActionItem(
          muted ? Icons.notifications_off_outlined : Icons.volume_up_rounded,
          'Звук',
          onMute,
        ),
        _ActionItem(Icons.logout_rounded, 'Выйти', onLeave),
        _ActionItem(Icons.more_horiz_rounded, 'Ещё', onMore),
      ]);
    } else {
      actions.addAll([
        _ActionItem(Icons.chat_bubble_outline_rounded, 'Чат', onChat),
        _ActionItem(Icons.search_rounded, 'Поиск', onSearch),
        _ActionItem(
          muted ? Icons.notifications_off_outlined : Icons.volume_up_rounded,
          'Звук',
          onMute,
        ),
        _ActionItem(Icons.more_horiz_rounded, 'Ещё', onMore),
      ]);
    }

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(width: 0.5, height: 40, color: p.border1),
            Expanded(
              child: InkWell(
                onTap: actions[i].onTap,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(actions[i].icon, color: p.lime, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      actions[i].label,
                      style: TextStyle(
                        color: p.text1,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionItem(this.icon, this.label, this.onTap);
}

class _InfoCard extends StatelessWidget {
  final String phone;
  final String nick;
  final String about;
  final bool isGroup;
  final VoidCallback onPhone;
  final VoidCallback? onNick;

  const _InfoCard({
    required this.phone,
    required this.nick,
    required this.about,
    required this.isGroup,
    required this.onPhone,
    required this.onNick,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = <Widget>[];

    if (phone.isNotEmpty && !isGroup) {
      rows.add(_InfoRow(
        title: 'МОБИЛЬНЫЙ',
        value: phone,
        valueColor: p.lime,
        trailing: Icon(Icons.phone_rounded, color: p.lime, size: 20),
        onTap: onPhone,
      ));
    }
    if (nick.isNotEmpty) {
      rows.add(_InfoRow(
        title: isGroup ? 'УНИКАЛЬНОЕ ИМЯ ГРУППЫ' : 'УНИКАЛЬНОЕ ИМЯ',
        value: nick.toLowerCase(),
        valueColor: p.lime,
        trailing: Icon(
          isGroup ? Icons.share_outlined : Icons.copy_rounded,
          color: p.lime,
          size: 20,
        ),
        onTap: onNick,
      ));
    }
    if (about.isNotEmpty) {
      rows.add(_InfoRow(
        title: isGroup ? 'ОПИСАНИЕ' : 'О СЕБЕ',
        value: about,
        valueColor: p.text1,
        multiline: true,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(height: 0.5, thickness: 0.5, color: p.border1),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool multiline;

  const _InfoRow({
    required this.title,
    required this.value,
    required this.valueColor,
    this.trailing,
    this.onTap,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: multiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: p.text3, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(color: valueColor, fontSize: 15),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              SizedBox(width: 40, height: 40, child: Center(child: trailing)),
          ],
        ),
      ),
    );
  }
}

class _AddMemberButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddMemberButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.bg2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 46,
          width: double.infinity,
          child: Center(
            child: Text(
              'Добавить участника',
              style: TextStyle(
                color: p.lime,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  final List<_MediaTab> tabs;
  final _MediaTab active;
  final ValueChanged<_MediaTab> onSelect;

  const _TabStrip({
    required this.tabs,
    required this.active,
    required this.onSelect,
  });

  String _label(_MediaTab t) => switch (t) {
        _MediaTab.members => 'Участники',
        _MediaTab.photos => 'Фото',
        _MediaTab.videos => 'Видео',
        _MediaTab.files => 'Файлы',
        _MediaTab.voice => 'Голосовые',
        _MediaTab.links => 'Ссылки',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = tabs[i];
          final selected = t == active;
          return InkWell(
            onTap: () => onSelect(t),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? p.lime.withValues(alpha: 0.15) : p.bg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _label(t),
                style: TextStyle(
                  color: selected ? p.lime : p.text3,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  final _MediaTab tab;
  final List<DlgInfoMember> members;
  final _MediaBuckets media;

  const _TabBody({
    required this.tab,
    required this.members,
    required this.media,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    switch (tab) {
      case _MediaTab.members:
        return Column(
          children: [
            for (final m in members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AvatarWidget(
                  name: m.name,
                  avatarUrl: m.avatarUrl,
                  colAvaId: m.colAvaId,
                  online: m.online,
                  size: 44,
                ),
                title: Text(m.name, style: TextStyle(color: p.text1)),
                subtitle: Text(
                  m.online
                      ? 'в сети'
                      : (m.roleName?.isNotEmpty == true
                          ? m.roleName!
                          : 'был(а) недавно'),
                  style: TextStyle(color: p.text2, fontSize: 12),
                ),
              ),
          ],
        );
      case _MediaTab.photos:
        return _MediaGrid(files: media.photos);
      case _MediaTab.videos:
        return _MediaGrid(files: media.videos, isVideo: true);
      case _MediaTab.files:
        return Column(
          children: [
            for (final f in media.files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.insert_drive_file_outlined, color: p.lime),
                title: Text(f.title, style: TextStyle(color: p.text1)),
                subtitle: f.subtitle.isEmpty
                    ? null
                    : Text(f.subtitle, style: TextStyle(color: p.text2)),
              ),
          ],
        );
      case _MediaTab.voice:
        return Column(
          children: [
            for (final v in media.voices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.mic_none_rounded, color: p.lime),
                title: Text(
                  v.fr_name.isNotEmpty ? v.fr_name : 'Голосовое',
                  style: TextStyle(color: p.text1),
                ),
                subtitle: Text(
                  v.dtshow.isNotEmpty ? v.dtshow : v.dttmcr,
                  style: TextStyle(color: p.text2, fontSize: 12),
                ),
              ),
          ],
        );
      case _MediaTab.links:
        return Column(
          children: [
            for (final l in media.links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.link_rounded, color: p.lime),
                title: Text(
                  l.link,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.lime, fontSize: 14),
                ),
                subtitle: Text(
                  [l.name, l.time].where((e) => e.isNotEmpty).join(' · '),
                  style: TextStyle(color: p.text2, fontSize: 12),
                ),
                onTap: () => launchUrl(Uri.parse(l.link)),
              ),
          ],
        );
    }
  }
}

class _MediaGrid extends StatelessWidget {
  final List<MediaFile> files;
  final bool isVideo;

  const _MediaGrid({required this.files, this.isVideo = false});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: files.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, i) {
        final f = files[i];
        final url = f.preview.isNotEmpty ? f.preview : f.url;
        return GestureDetector(
          onTap: () {
            if (!isVideo) FullscreenImageViewer.show(context, f);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isNotEmpty)
                CachedForumImage(url: url, fit: BoxFit.cover)
              else
                ColoredBox(color: context.palette.bg3),
              if (isVideo)
                const Center(
                  child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaBuckets {
  final List<MediaFile> photos;
  final List<MediaFile> videos;
  final List<_FileRow> files;
  final List<MessageViewModel> voices;
  final List<_LinkRow> links;

  const _MediaBuckets({
    required this.photos,
    required this.videos,
    required this.files,
    required this.voices,
    required this.links,
  });
}

class _FileRow {
  final String title;
  final String subtitle;
  final String url;
  const _FileRow({
    required this.title,
    required this.subtitle,
    required this.url,
  });
}

class _LinkRow {
  final String link;
  final String name;
  final String time;
  const _LinkRow({
    required this.link,
    required this.name,
    required this.time,
  });
}
