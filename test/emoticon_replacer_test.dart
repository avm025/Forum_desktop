import 'package:forum_app/utils/emoticon_replacer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replaces common emoticons in plain text', () {
    expect(EmoticonReplacer.replace('Привет :)'), 'Привет 🙂');
    expect(EmoticonReplacer.replace('test ;-) :D'), 'test 😉 😄');
    expect(EmoticonReplacer.replace(':-)'), '🙂');
    expect(EmoticonReplacer.replace('no emoticons'), 'no emoticons');
    expect(EmoticonReplacer.replace(':|'), '😐');
  });

  test('does not replace inside URLs', () {
    const url = 'https://example.com/path';
    expect(EmoticonReplacer.replace(url), url);
    expect(
      EmoticonReplacer.replace('смотри https://site.com/foo :)'),
      'смотри https://site.com/foo 🙂',
    );
  });

  test('does not replace inside JSON payloads', () {
    const json = '{"desc":"hello :)","url":"https://x.com"}';
    expect(EmoticonReplacer.replace(json), json);
  });

  test('does not replace inside HTML', () {
    const html = '<a href="https://x.com">link :)</a>';
    expect(EmoticonReplacer.replace(html), html);
  });

  test('does not break html-like closing tags', () {
    expect(EmoticonReplacer.replace('</html>'), '</html>');
    expect(EmoticonReplacer.replace('<3'), '❤️');
  });
}
