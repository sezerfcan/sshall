import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/match_highlight.dart';

const _base = TextStyle(fontSize: 12);
const _hit = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

void main() {
  test('splits the matched substring into a hit span', () {
    final spans = highlightMatch(
      'web-deploy',
      'deploy',
      base: _base,
      hit: _hit,
    );
    expect(spans.map((s) => s.text).toList(), ['web-', 'deploy']);
    expect(spans[0].style, _base);
    expect(spans[1].style, _hit);
  });

  test('is case-insensitive but keeps original casing', () {
    final spans = highlightMatch(
      'Production',
      'production',
      base: _base,
      hit: _hit,
    );
    expect(spans.single.text, 'Production');
    expect(spans.single.style, _hit);
  });

  test('match in the middle yields base/hit/base', () {
    final spans = highlightMatch('my-web-1', 'web', base: _base, hit: _hit);
    expect(spans.map((s) => s.text).toList(), ['my-', 'web', '-1']);
    expect(spans[1].style, _hit);
  });

  test('no match yields a single base span', () {
    final spans = highlightMatch('laptop', 'zzz', base: _base, hit: _hit);
    expect(spans.single.text, 'laptop');
    expect(spans.single.style, _base);
  });

  test('blank query yields a single base span', () {
    final spans = highlightMatch('laptop', '   ', base: _base, hit: _hit);
    expect(spans.single.text, 'laptop');
    expect(spans.single.style, _base);
  });

  test('multiple occurrences are all highlighted', () {
    final spans = highlightMatch('aXaXa', 'X', base: _base, hit: _hit);
    expect(spans.map((s) => s.text).toList(), ['a', 'X', 'a', 'X', 'a']);
    expect(spans[1].style, _hit);
    expect(spans[3].style, _hit);
  });
}
