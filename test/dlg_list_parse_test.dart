import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/api/dialog_mapper.dart';

void main() {
  test('dlg with geotr last_msg', () {
    final d = DialogMapper.fromServerJson({
      'usr_id': '77086353046191',
      'dlg_id': '1326',
      'is_grp': 0,
      'name': 'Андрей 2',
      'last_msg': {
        'id': 588890,
        'body':
            '{"lat":54.7171814,"lon":20.4970616,"comp":180.8,"speed":0.75,"live":1,"id":"77086353046191"}',
        'type': 'geotr',
        'fr_id': '77086353046191',
        'dlg_id': 1326,
        'dttmcr': '2026-09-07T17:13:46.316293+03:00',
        'status': 2,
        'fr_name': 'Андрей 2',
      },
      'usr1_id': '77086353046191',
      'usr2_id': '804341128831559',
      'usr1_name': 'Андрей 2',
      'usr2_name': 'Андрей',
      'col_ava_id': 8,
    }, currentUserId: '804341128831559');
    expect(d.last_msg, 'Трансляция геопозиции');
    expect(d.chatName, 'Андрей 2');
  });

  test('dlg with ended geotr last_msg', () {
    final d = DialogMapper.fromServerJson({
      'usr_id': '77086353046191',
      'dlg_id': '1326',
      'is_grp': 0,
      'name': 'Андрей 2',
      'last_msg': {
        'id': 588891,
        'body': '{"lat":54.71,"lon":20.49,"live":0,"id":"77086353046191"}',
        'type': 'geotr',
        'fr_id': '77086353046191',
        'dlg_id': 1326,
        'dttmcr': '2026-09-07T17:20:00.000+03:00',
        'status': 2,
        'fr_name': 'Андрей 2',
      },
      'usr1_id': '77086353046191',
      'usr2_id': '804341128831559',
    }, currentUserId: '804341128831559');
    expect(d.last_msg, 'Трансляция геопозиции завершена');
  });

  test('dlg with txt last_msg', () {
    final d = DialogMapper.fromServerJson({
      'dlg_id': '770',
      'is_grp': 1,
      'name': 'Форум ИИ',
      'last_msg': {
        'id': 495416,
        'body': 'щщщ',
        'type': 'txt',
        'fr_id': '804341128831559',
        'fr_name': 'Андрей',
        'status': 0,
        'dttmcr': '2026-06-26T14:25:47.370327+03:00',
      },
      'usr1_id': '804341128831559',
      'usr2_id': 'AI',
      'ai': 8,
      'col_ava_id': 10,
    }, currentUserId: '804341128831559');
    expect(d.last_msg, 'щщщ');
  });

  test('dlg with media last_msg', () {
    final body = jsonEncode({
      'desc': '',
      'files': [
        {'kind': 'jpg', 'fname': 'a.jpg', 'fdir': '2026-06-22/'}
      ]
    });
    final d = DialogMapper.fromServerJson({
      'dlg_id': '680',
      'is_grp': 1,
      'name': 'Forum dev',
      'last_msg': {
        'id': 397027,
        'body': body,
        'type': 'media',
        'fr_id': '1',
        'fr_name': 'Sergei',
        'status': 2,
        'dttmcr': '2026-06-22T03:26:24.885193+03:00',
      },
      'col_ava_id': 6,
    });
    expect(d.last_msg, 'Медиафайлы');
  });
}
