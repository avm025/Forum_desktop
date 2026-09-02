import '../models/dialogs_list_view_model.dart';
import '../models/global_search_chat_group.dart';
import '../models/global_search_hit.dart';
import '../models/global_search_scope.dart';
import '../models/media_file.dart';
import '../models/message_view_model.dart';
import '../utils/file_kind.dart';
import '../utils/media_display_name.dart';

/// Поиск по чатам и вложениям в загруженных сообщениях диалогов.
class GlobalSearch {
  GlobalSearch._();

  static const _imageKinds = {
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

  static bool _matches(String haystack, String query) {
    if (query.isEmpty) return true;
    return haystack.toLowerCase().contains(query);
  }

  static String _messageText(MessageViewModel m) {
    final parts = <String>[
      m.body,
      m.text,
      m.desc,
      m.fileTitle ?? '',
      m.fr_name,
    ];
    return parts.where((p) => p.trim().isNotEmpty).join(' ');
  }

  static bool _isImageFile(MediaFile f) {
    if (f.isVideo || FileKind.isVideoKind(f.kind)) return false;
    final kind = f.kind.toLowerCase();
    final ext = FileKind.extensionFromName(
      f.fname.isNotEmpty ? f.fname : f.title,
    );
    return _imageKinds.contains(kind) || _imageKinds.contains(ext);
  }

  static List<DialogsListViewModel> filterChats(
    Iterable<DialogsListViewModel> dialogs,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return dialogs.toList();
    return dialogs
        .where(
          (d) =>
              d.chatName.toLowerCase().contains(q) ||
              d.last_msg.toLowerCase().contains(q),
        )
        .toList();
  }

  static List<GlobalSearchHit> searchMedia(
    Iterable<DialogsListViewModel> dialogs,
    String query,
    GlobalSearchScope scope,
  ) {
    final groups = searchMediaGrouped(dialogs, query, scope);
    return [for (final g in groups) ...g.hits];
  }

  /// Совпадения, сгруппированные по чатам (порядок чатов — как в списке).
  static List<GlobalSearchChatGroup> searchMediaGrouped(
    Iterable<DialogsListViewModel> dialogs,
    String query,
    GlobalSearchScope scope,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || scope == GlobalSearchScope.chats) return const [];

    final groups = <GlobalSearchChatGroup>[];
    for (final dialog in dialogs) {
      final hits = <GlobalSearchHit>[];
      for (final message in dialog.messages) {
        hits.addAll(_hitsForMessage(dialog, message, scope, q));
      }
      if (hits.isEmpty) continue;
      hits.sort((a, b) => b.message.dttmcr.compareTo(a.message.dttmcr));
      groups.add(GlobalSearchChatGroup(dialog: dialog, hits: hits));
    }
    return groups;
  }

  static List<GlobalSearchHit> _hitsForMessage(
    DialogsListViewModel dialog,
    MessageViewModel message,
    GlobalSearchScope scope,
    String q,
  ) {
    final chatName = dialog.chatName;
    final msgText = _messageText(message);
    final baseSubtitle = [
      chatName,
      if (message.dtshow.isNotEmpty) message.dtshow,
    ].join(' · ');

    bool textMatches(String value) => _matches(value, q);
    bool blobMatches(String a, String b, String c) =>
        textMatches(a) || textMatches(b) || textMatches(c) || textMatches(chatName);

    if (scope == GlobalSearchScope.voice) {
      if (!message.isVoice) return const [];
      if (!blobMatches(msgText, message.body, message.text)) return const [];
      return [
        GlobalSearchHit(
          scope: scope,
          dialog: dialog,
          message: message,
          title: 'Голосовое сообщение',
          subtitle: baseSubtitle,
        ),
      ];
    }

    final results = <GlobalSearchHit>[];

    void addFileHit(MediaFile file, GlobalSearchScope fileScope) {
      if (fileScope != scope) return;
      final title = MediaDisplayName.forFile(file, dttmcr: message.dttmcr);
      if (!blobMatches(title, file.fname, msgText) &&
          !textMatches(chatName)) {
        return;
      }
      results.add(GlobalSearchHit(
        scope: fileScope,
        dialog: dialog,
        message: message,
        file: file,
        title: title,
        subtitle: baseSubtitle,
      ));
    }

    if (message.files.isNotEmpty) {
      for (final raw in message.files) {
        if (raw.isVideo || FileKind.isVideoKind(raw.kind)) {
          addFileHit(raw, GlobalSearchScope.videos);
        } else if (_isImageFile(raw)) {
          addFileHit(raw, GlobalSearchScope.photos);
        } else {
          addFileHit(raw, GlobalSearchScope.files);
        }
      }
      return results;
    }

    final t = message.type.toLowerCase();
    if (scope == GlobalSearchScope.files &&
        (t == 'file' || message.isFile)) {
      final title = MediaDisplayName.resolve(
        title: message.fileTitle,
        fname: message.text,
        dttmcr: message.dttmcr,
      );
      if (!blobMatches(title, msgText, message.text) &&
          !textMatches(chatName)) {
        return const [];
      }
      results.add(GlobalSearchHit(
        scope: scope,
        dialog: dialog,
        message: message,
        title: title,
        subtitle: baseSubtitle,
      ));
      return results;
    }

    if (scope == GlobalSearchScope.videos && t == 'video') {
      if (!blobMatches(msgText, message.url, message.preview) &&
          !textMatches(chatName)) {
        return const [];
      }
      results.add(GlobalSearchHit(
        scope: scope,
        dialog: dialog,
        message: message,
        title: MediaDisplayName.resolve(
          title: message.fileTitle,
          dttmcr: message.dttmcr,
        ),
        subtitle: baseSubtitle,
      ));
      return results;
    }

    if (scope == GlobalSearchScope.photos &&
        (t == 'image' || t == 'img' || t == 'photo' || t == 'media')) {
      if (!blobMatches(msgText, message.url, message.preview) &&
          !textMatches(chatName)) {
        return const [];
      }
      final caption = msgText.trim();
      results.add(GlobalSearchHit(
        scope: scope,
        dialog: dialog,
        message: message,
        title: caption.isNotEmpty && !MediaDisplayName.isTechnicalFileName(caption)
            ? caption
            : MediaDisplayName.resolve(
                title: message.fileTitle,
                dttmcr: message.dttmcr,
              ),
        subtitle: baseSubtitle,
      ));
    }

    return results;
  }
}
