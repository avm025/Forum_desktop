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
import '../../services/media_thumb_cache.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/file_kind.dart';
import '../../utils/media_display_name.dart';
import '../../utils/media_file_loader.dart';
import '../../utils/media_file_url.dart';
import '../../utils/reaction_utils.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/cached_forum_image.dart';
import '../../widgets/chat_attachment_viewer.dart';
import '../../widgets/profile_content_frame.dart';
import '../../widgets/voice_message.dart';

/// Профиль собеседника / группы — порт iOS `AnotherProfileViewController`.
class PeerProfileScreen extends StatefulWidget {
  final String dialogId;

  const PeerProfileScreen({super.key, required this.dialogId});

  static Future<void> open(BuildContext context, DialogsListViewModel dialog) {
    final id = dialog.id?.trim() ?? '';
    if (id.isEmpty) return Future.value();
    // rootNavigator: локальный Navigator в панели чата убран (краш Overlay).
    return Navigator.of(context, rootNavigator: true).push(
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

  void _openChatSearch() {
    final dlgId = widget.dialogId.trim();
    if (dlgId.isEmpty) return;
    context.read<AppState>().requestChatSearch(dlgId);
    Navigator.of(context).pop();
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

  static bool _isImageMediaFile(MediaFile f) {
    if (f.isVideo) return false;
    const images = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
      'img',
      'image',
    };
    final kind = f.kind.toLowerCase();
    final ext = FileKind.extensionFromName(
      f.fname.isNotEmpty ? f.fname : f.title,
    );
    return images.contains(kind) || images.contains(ext);
  }

  MediaFile _normalizeMediaFile(MediaFile source, MessageViewModel? message) {
    final file = MediaFile(
      hash: source.hash,
      url: source.url,
      fname: source.fname,
      fdir: source.fdir,
      kind: source.kind,
      preview: source.preview,
      title: source.title,
      size: source.size,
      width: source.width,
      height: source.height,
      duration: source.duration,
      uploaded: source.uploaded,
      URL: source.URL,
      bytes: source.bytes,
    );

    if (file.fname.trim().isEmpty && message != null) {
      final title = (message.fileTitle ?? '').trim();
      if (title.isNotEmpty) file.fname = title;
    }
    file.title = MediaDisplayName.forFile(
      file,
      dttmcr: message?.dttmcr,
    );
    if (file.url.trim().isEmpty && message != null) {
      file.url = message.url;
      file.fdir = message.fdir;
    }
    if (file.preview.trim().isEmpty && message != null) {
      file.preview = message.preview;
    }
    if (file.url.trim().isEmpty) {
      file.url = MediaFileUrl.resolve(file);
    }
    return file;
  }

  MediaFile _legacyFileFromMessage(MessageViewModel m) {
    final title = MediaDisplayName.resolve(
      title: m.fileTitle ?? m.text,
      dttmcr: m.dttmcr,
    );
    return _normalizeMediaFile(
      MediaFile(
        url: m.url,
        fdir: m.fdir,
        fname: title,
        title: title,
        kind: (m.fileFormat ?? FileKind.kindFromName(title)).toLowerCase(),
      ),
      m,
    );
  }

  _MediaBuckets _collectMedia(List<MessageViewModel> messages) {
    final photos = <MediaFile>[];
    final videos = <MediaFile>[];
    final files = <MediaFile>[];
    final voices = <MessageViewModel>[];
    final links = <_LinkRow>[];

    for (final m in messages) {
      final t = m.type.toLowerCase();
      if (t == 'voice' || m.isVoice) {
        voices.add(m);
        continue;
      }
      if (m.files.isNotEmpty) {
        for (final raw in m.files) {
          final f = _normalizeMediaFile(raw, m);
          if (f.isVideo || FileKind.isVideoKind(f.kind)) {
            videos.add(f);
          } else if (_isImageMediaFile(f)) {
            photos.add(f);
          } else {
            files.add(f);
          }
        }
        continue;
      }
      if (t == 'file' || m.isFile) {
        files.add(_legacyFileFromMessage(m));
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
        continue;
      }
      if (t == 'video') {
        videos.add(_normalizeMediaFile(
          MediaFile(url: m.url, preview: m.preview, kind: 'mp4'),
          m,
        ));
      } else if (t == 'image' || t == 'img' || t == 'photo' || t == 'media') {
        if (m.url.isNotEmpty || m.preview.isNotEmpty) {
          photos.add(_normalizeMediaFile(
            MediaFile(url: m.url, preview: m.preview),
            m,
          ));
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
                child: ProfileContentFrame(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        canCall: !dialog.fav &&
                            (isGrp ||
                                (dialog.usr_id?.trim().isNotEmpty ?? false)),
                        muted: _muted,
                        onAudioCall: () => context
                            .read<AppState>()
                            .startCallFromChat(video: false),
                        onVideoCall: () => context
                            .read<AppState>()
                            .startCallFromChat(video: true),
                        onSearch: _openChatSearch,
                        onMute: () => setState(() => _muted = !_muted),
                        onLeave: () => _onMoreAction(dialog, 'Покинуть группу'),
                        onMore: () => _showMoreMenu(dialog),
                        onFavSearch: _openChatSearch,
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
              padding: const EdgeInsets.symmetric(
                horizontal: ProfileLayout.horizontalInset,
                vertical: 4,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ProfileLayout.maxContentWidth,
                  ),
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
    return ProfileContentFrame(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
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
        ),
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
  final bool canCall;
  final bool muted;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;
  final VoidCallback onSearch;
  final VoidCallback onMute;
  final VoidCallback onLeave;
  final VoidCallback onMore;
  final VoidCallback onFavSearch;
  final VoidCallback onFavClear;

  const _ActionStrip({
    required this.fav,
    required this.isGroup,
    required this.canCall,
    required this.muted,
    required this.onAudioCall,
    required this.onVideoCall,
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
      if (canCall) {
        actions.addAll([
          _ActionItem(Icons.call_rounded, 'Аудио', onAudioCall),
          _ActionItem(Icons.videocam_rounded, 'Видео', onVideoCall),
        ]);
      }
      actions.addAll([
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.text3, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    textAlign: TextAlign.center,
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
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                InkWell(
                  onTap: () => onSelect(tabs[i]),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tabs[i] == active
                          ? p.lime.withValues(alpha: 0.15)
                          : p.bg2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _label(tabs[i]),
                      style: TextStyle(
                        color: tabs[i] == active ? p.lime : p.text3,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
              _ProfileFileRow(key: ValueKey(f.hash + f.url + f.fname), file: f),
          ],
        );
      case _MediaTab.voice:
        return Column(
          children: [
            for (final v in media.voices)
              _ProfileVoiceRow(
                key: ValueKey(v.id + v.hash + v.dttmcr),
                message: v,
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
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) {
        return _ProfileMediaCell(
          key: ValueKey('${files[i].hash}_${files[i].url}_${files[i].fname}'),
          file: files[i],
          isVideo: isVideo,
        );
      },
    );
  }
}

/// Превью фото/видео в профиле + открытие через тот же viewer, что в чате.
class _ProfileMediaCell extends StatelessWidget {
  final MediaFile file;
  final bool isVideo;

  const _ProfileMediaCell({
    super.key,
    required this.file,
    required this.isVideo,
  });

  String get _imageUrl {
    final preview = file.preview.trim();
    if (preview.startsWith('http://') || preview.startsWith('https://')) {
      return preview;
    }
    return MediaFileUrl.resolve(file);
  }

  Future<void> _open(BuildContext context) async {
    try {
      await ChatAttachmentViewer.show(context, file);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () => _open(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isVideo)
                _ProfileVideoThumb(file: file)
              else
                CachedForumImage(
                  url: _imageUrl,
                  fit: BoxFit.cover,
                ),
              if (isVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white70,
                    size: 32,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileVideoThumb extends StatefulWidget {
  final MediaFile file;

  const _ProfileVideoThumb({required this.file});

  @override
  State<_ProfileVideoThumb> createState() => _ProfileVideoThumbState();
}

class _ProfileVideoThumbState extends State<_ProfileVideoThumb> {
  ImageProvider? _thumb;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await MediaThumbCache.ensureThumbnail(widget.file);
      if (mounted) {
        setState(() {
          _thumb = FileImage(file);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_thumb != null) {
      return Image(image: _thumb!, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (_loading) {
      return ColoredBox(
        color: p.bg3,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.lime),
          ),
        ),
      );
    }
    return ColoredBox(
      color: p.bg3,
      child: Icon(Icons.videocam_outlined, color: p.text3),
    );
  }
}

/// Строка голосового в профиле — как файлы: слева, на всю ширину.
class _ProfileVoiceRow extends StatelessWidget {
  final MessageViewModel message;

  const _ProfileVoiceRow({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = message.fr_name.isNotEmpty ? message.fr_name : 'Голосовое';
    final time = message.dtshow.isNotEmpty ? message.dtshow : message.dttmcr;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.bg2,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.mic_none_rounded, color: p.lime, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text1, fontSize: 15),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: TextStyle(color: p.text2, fontSize: 12),
                      ),
                    const SizedBox(height: 6),
                    VoiceMessage(message: message, expand: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка файла в профиле: скрепка = ещё не загружен на диск.
class _ProfileFileRow extends StatefulWidget {
  final MediaFile file;

  const _ProfileFileRow({super.key, required this.file});

  @override
  State<_ProfileFileRow> createState() => _ProfileFileRowState();
}

class _ProfileFileRowState extends State<_ProfileFileRow> {
  bool _downloaded = false;
  bool _checking = true;
  bool _busy = false;
  ImageProvider? _preview;

  MediaFile get file => widget.file;

  String get _title => MediaDisplayName.forFile(file);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _checking = true;
      _preview = null;
    });
    final downloaded = await MediaFileLoader.isDownloaded(
      file,
      downloadUrl: MediaFileUrl.resolve(file),
    );
    if (!mounted) return;
    setState(() {
      _downloaded = downloaded;
      _checking = false;
    });
    await _loadPreview();
  }

  bool _looksLikeImage() {
    final name = file.fname.isNotEmpty ? file.fname : file.title;
    return FileKind.isImageKind(file.kind) || FileKind.isImageName(name);
  }

  Future<void> _loadPreview() async {
    if (!_looksLikeImage()) return;
    try {
      final thumb = await MediaThumbCache.ensureThumbnail(file);
      if (mounted) setState(() => _preview = FileImage(thumb));
    } catch (_) {}
  }

  Future<void> _ensureAndOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_downloaded) {
        await MediaFileLoader.ensureCached(
          file,
          downloadUrl: MediaFileUrl.resolve(file),
        );
        if (!mounted) return;
        setState(() => _downloaded = true);
      }
      if (!mounted) return;
      await ChatAttachmentViewer.show(context, file);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть файл')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final meta = [
      if (file.humanSize.isNotEmpty) file.humanSize,
      if (file.formatLabel.isNotEmpty) file.formatLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.bg2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _ensureAndOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _preview != null
                              ? Image(image: _preview!, fit: BoxFit.cover)
                              : Center(
                                  child: Text(
                                    file.formatLabel.isNotEmpty
                                        ? file.formatLabel
                                        : 'FILE',
                                    style: TextStyle(
                                      color: p.purple,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (!_downloaded && !_checking)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28),
                          child: Center(
                            child: Icon(
                              Icons.attach_file_rounded,
                              color: p.lime,
                              size: 22,
                            ),
                          ),
                        )
                      else if (_downloaded && !_checking && !_busy)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.folder_rounded,
                                color: p.lime,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      if (_checking || _busy)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: p.lime,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text1, fontSize: 15),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: TextStyle(color: p.text2, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaBuckets {
  final List<MediaFile> photos;
  final List<MediaFile> videos;
  final List<MediaFile> files;
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
