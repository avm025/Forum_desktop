/// Режим запроса msg_list (см. WS_MSG_LIST.md).
class MsgListRequest {
  /// `true` — новые сообщения после last_id; `false` — история через first_id.
  final bool getNew;
  final String? firstId;
  final String? lastId;
  final String? lastDt;

  const MsgListRequest._({
    required this.getNew,
    this.firstId,
    this.lastId,
    this.lastDt,
  });

  /// Первая загрузка — локальный кэш пуст.
  factory MsgListRequest.initial() => const MsgListRequest._(
        getNew: false,
        firstId: '0',
      );

  /// Подгрузка истории вверх.
  factory MsgListRequest.history(String oldestMessageId) => MsgListRequest._(
        getNew: false,
        firstId: oldestMessageId,
      );

  /// Догрузка новых сообщений после last_id / last_dt.
  factory MsgListRequest.newer({
    required String lastId,
    required String lastDt,
  }) =>
      MsgListRequest._(
        getNew: true,
        lastId: lastId,
        lastDt: lastDt,
      );
}
