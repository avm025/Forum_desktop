import 'dart:convert';

/// Разбор body `type=call` и тексты для пузыря / списка / reply
/// (iOS `DataConverter.callDisplay` / `callPreviewText`).
/// Документация: https://4um.me:7770/api_forum_doc/ → msg_call
class CallMessageBody {
  final String media; // audio | video
  final String type; // missed | cancelled | talk
  final int duration;
  final String rejectUsrId;
  final String callId;

  const CallMessageBody({
    this.media = 'audio',
    this.type = 'missed',
    this.duration = 0,
    this.rejectUsrId = '',
    this.callId = '',
  });

  bool get isVideo => media.toLowerCase() == 'video';
  bool get isTalk => type.toLowerCase() == 'talk';
  bool get isFailed => !isTalk; // missed | cancelled

  static CallMessageBody? tryParse(dynamic raw) {
    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;

    final media = (map['media']?.toString() ?? 'audio').trim().toLowerCase();
    final type = (map['type']?.toString() ??
            map['call_type']?.toString() ??
            'missed')
        .trim()
        .toLowerCase();
    final durationRaw = map['duration'];
    final duration = durationRaw is int
        ? durationRaw
        : int.tryParse(durationRaw?.toString() ?? '') ?? 0;

    return CallMessageBody(
      media: media == 'video' ? 'video' : 'audio',
      type: type == 'talk' || type == 'cancelled' || type == 'missed'
          ? type
          : 'missed',
      duration: duration < 0 ? 0 : duration,
      rejectUsrId: map['reject_usr_id']?.toString().trim() ?? '',
      callId: map['call_id']?.toString().trim() ?? '',
    );
  }
}

class CallMessageDisplay {
  final String title;
  final String subtitle;
  final CallMessageBody body;

  const CallMessageDisplay({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  String get previewText {
    final sub = subtitle.trim();
    if (sub.isEmpty) return title;
    return '$title · $sub';
  }

  /// Логика iOS `DataConverter.callDisplay(body:frId:)`.
  static CallMessageDisplay resolve({
    required CallMessageBody body,
    required String? frId,
    required String? currentUserId,
  }) {
    final outgoing = sameUserId(frId, currentUserId);
    final type = body.type.toLowerCase();

    if (type == 'talk') {
      return CallMessageDisplay(
        title: outgoing ? 'Исходящий вызов' : 'Входящий вызов',
        subtitle: body.duration > 0 ? formatCallDuration(body.duration) : '',
        body: body,
      );
    }

    if (type == 'cancelled') {
      final cancelledByCaller =
          body.rejectUsrId.isEmpty || sameUserId(body.rejectUsrId, frId);
      if (outgoing) {
        return CallMessageDisplay(
          title: 'Исходящий вызов',
          subtitle: cancelledByCaller ? 'отменен' : 'отклонён',
          body: body,
        );
      }
      if (cancelledByCaller) {
        return CallMessageDisplay(
          title: 'Пропущенный вызов',
          subtitle: 'отменен',
          body: body,
        );
      }
      return CallMessageDisplay(
        title: 'Входящий вызов',
        subtitle: 'отклонён',
        body: body,
      );
    }

    // missed
    return CallMessageDisplay(
      title: outgoing ? 'Исходящий вызов' : 'Пропущенный вызов',
      subtitle: 'нет ответа',
      body: body,
    );
  }

  static CallMessageDisplay? tryResolve({
    required dynamic bodyRaw,
    required String? frId,
    required String? currentUserId,
  }) {
    final parsed = CallMessageBody.tryParse(bodyRaw);
    if (parsed == null) return null;
    return resolve(
      body: parsed,
      frId: frId,
      currentUserId: currentUserId,
    );
  }

  /// `m:ss` или `h:mm:ss`.
  static String formatCallDuration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  static bool sameUserId(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    final xi = int.tryParse(x);
    final yi = int.tryParse(y);
    return xi != null && yi != null && xi == yi;
  }
}
