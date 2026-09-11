import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/api/message_mapper.dart';

void main() {
  test('geo body as JSON string', () {
    final m = MessageMapper.fromServerJson({
      'type': 'geo',
      'id': '1',
      'fr_id': 'u1',
      'fr_name': 'A',
      'body': jsonEncode({
        'lat': 55.75,
        'lon': 37.61,
        'adrs': 'Москва',
      }),
      'dttmcr': '2026-01-01T12:00:00.000Z',
    });
    expect(m.type, 'location');
    expect(m.isLocation, isTrue);
    expect(m.latitude, 55.75);
    expect(m.longitude, 37.61);
    expect(m.address, 'Москва');
  });

  test('geo body as Map and uppercase type', () {
    final m = MessageMapper.fromServerJson({
      'type': 'GEO',
      'id': '2',
      'fr_id': 'u1',
      'fr_name': 'A',
      'body': {
        'lat': 44.6,
        'lon': 33.5,
        'adrs': 'Севастополь',
      },
      'dttmcr': '2026-01-01T12:00:00.000Z',
    });
    expect(m.type, 'location');
    expect(m.isLocation, isTrue);
    expect(m.latitude, 44.6);
    expect(m.longitude, 33.5);
    expect(m.address, 'Севастополь');
  });

  test('geotr live track body', () {
    final m = MessageMapper.fromServerJson({
      'type': 'geotr',
      'id': '588890',
      'fr_id': 'u1',
      'fr_name': 'A',
      'body': jsonEncode({
        'lat': 54.7173235,
        'lon': 20.4970666,
        'comp': 0,
        'speed': 0,
        'live': 1,
        'id': '77086353046191',
      }),
      'dttmcr': '2026-09-07T14:13:46.316Z',
    });
    expect(m.type, 'location');
    expect(m.isLocation, isTrue);
    expect(m.latitude, closeTo(54.7173235, 1e-6));
    expect(m.longitude, closeTo(20.4970666, 1e-6));
    expect(m.address, 'Трансляция геопозиции');
    expect(m.locationLive, isTrue);
  });

  test('geotr live=0 ends the track', () {
    final m = MessageMapper.fromServerJson({
      'type': 'geotr',
      'id': '588891',
      'fr_id': 'u1',
      'fr_name': 'A',
      'body': jsonEncode({
        'lat': 54.7173235,
        'lon': 20.4970666,
        'live': 0,
        'id': '77086353046191',
      }),
      'dttmcr': '2026-09-07T14:20:00.000Z',
    });
    expect(m.isLocation, isTrue);
    expect(m.locationLive, isFalse);
    expect(m.address, 'Трансляция геопозиции завершена');
    expect(m.body, 'Трансляция геопозиции завершена');
  });
}
