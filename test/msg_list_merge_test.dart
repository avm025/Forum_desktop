import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/api/msg_list_merge.dart';
import 'package:forum_app/api/msg_list_result.dart';
import 'package:forum_app/models/dialogs_list_view_model.dart';
import 'package:forum_app/models/message_view_model.dart';

MessageViewModel _msg(String id) => MessageViewModel(
      id: id,
      type: 'text',
      body: id,
      text: id,
    );

void main() {
  test('replace keeps server tail instead of stale cache', () {
    final dialog = DialogsListViewModel(
      id: '1',
      messages: [_msg('old-1'), _msg('old-2')],
    );
    final incoming = [_msg('new-1'), _msg('new-2'), _msg('new-3')];

    MsgListMerge.apply(
      dialog: dialog,
      result: MsgListResult(
        messages: incoming,
        isHistory: true,
        hasMoreHistory: true,
      ),
      replace: true,
      onHistoryPagination: (_) {},
    );

    expect(dialog.messages.map((m) => m.id), ['new-1', 'new-2', 'new-3']);
  });

  test('history without replace prepends onto cache', () {
    final dialog = DialogsListViewModel(
      id: '1',
      messages: [_msg('cached')],
    );

    MsgListMerge.apply(
      dialog: dialog,
      result: MsgListResult(
        messages: [_msg('older'), _msg('cached')],
        isHistory: true,
      ),
      onHistoryPagination: (_) {},
    );

    expect(dialog.messages.map((m) => m.id), ['older', 'cached']);
  });

  test('live geotr updates merge onto the same bubble', () {
    final live = MessageViewModel(
      id: 'geo-1',
      type: 'location',
      fr_id: 'u1',
      latitude: 54.71,
      longitude: 20.49,
      address: 'Трансляция геопозиции',
      locationLive: true,
    );
    final dialog = DialogsListViewModel(id: '1', messages: [live]);
    final next = MessageViewModel(
      id: 'geo-2',
      type: 'location',
      fr_id: 'u1',
      latitude: 54.72,
      longitude: 20.50,
      address: 'Трансляция геопозиции',
      locationLive: true,
    );

    expect(
      MsgListMerge.applyIncoming(dialog: dialog, incoming: next),
      isTrue,
    );
    expect(dialog.messages, hasLength(1));
    expect(dialog.messages.single.id, 'geo-1');
    expect(dialog.messages.single.latitude, 54.72);
    expect(dialog.messages.single.locationLive, isTrue);
  });

  test('ended geotr updates the live bubble text', () {
    final live = MessageViewModel(
      id: 'geo-1',
      type: 'location',
      fr_id: 'u1',
      latitude: 54.71,
      longitude: 20.49,
      address: 'Трансляция геопозиции',
      locationLive: true,
    );
    final dialog = DialogsListViewModel(id: '1', messages: [live]);
    final ended = MessageViewModel(
      id: 'geo-end',
      type: 'location',
      fr_id: 'u1',
      latitude: 54.73,
      longitude: 20.51,
      address: 'Трансляция геопозиции завершена',
      locationLive: false,
    );

    MsgListMerge.applyIncoming(dialog: dialog, incoming: ended);
    expect(dialog.messages, hasLength(1));
    expect(dialog.messages.single.locationLive, isFalse);
    expect(dialog.messages.single.address, 'Трансляция геопозиции завершена');
  });
}
