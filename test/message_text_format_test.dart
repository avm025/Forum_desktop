import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/utils/message_text_format.dart';

void main() {
  test('**bold** and *italic*', () {
    expect(
      MessageTextFormat.plain('**Hello** and *world*'),
      'Hello and world',
    );
  });

  test('HTML anchor becomes link text', () {
    const raw =
        'See <a href="https://example.com/x">click</a> please';
    expect(MessageTextFormat.plain(raw), 'See click please');
  });

  test('nested markers in channel caption', () {
    const raw =
        '**Title**\n\nBody. <a href="https://max.ru/x">Подписывайтесь</a>';
    expect(
      MessageTextFormat.plain(raw),
      'Title\n\nBody. Подписывайтесь',
    );
  });

  test('rich span keeps children for bold', () {
    final recognizers = <TapGestureRecognizer>[];
    final span = MessageTextFormat.rich(
      raw: '**Bold**',
      style: const TextStyle(fontSize: 15),
      linkColor: const Color(0xFF0000FF),
      recognizers: recognizers,
      onLinkTap: (_) {},
    );
    expect(recognizers, isEmpty);
    expect(span.children, isNotNull);
    expect(span.children!.length, greaterThan(0));
    final first = span.children!.first as TextSpan;
    expect(first.text, 'Bold');
    expect(first.style?.fontWeight, FontWeight.w700);
  });
}
