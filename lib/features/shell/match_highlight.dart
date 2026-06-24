import 'package:flutter/widgets.dart';

/// Splits [text] into [TextSpan]s, styling every case-insensitive occurrence of
/// [query] with [hit] and the rest with [base] (ADR 0035 D3 — search match
/// highlighting). Pure: no widgets pumped, deterministic for golden coverage.
///
/// A blank query (or no match) yields a single [base] span, so callers can use
/// the result unconditionally. Matching is case-insensitive but the ORIGINAL
/// casing of [text] is preserved in the output.
List<TextSpan> highlightMatch(
  String text,
  String query, {
  required TextStyle base,
  required TextStyle hit,
}) {
  final q = query.trim();
  if (q.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: base)];
  }
  final lowerText = text.toLowerCase();
  final lowerQuery = q.toLowerCase();

  final spans = <TextSpan>[];
  var start = 0;
  while (true) {
    final idx = lowerText.indexOf(lowerQuery, start);
    if (idx < 0) {
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start), style: base));
      }
      break;
    }
    if (idx > start) {
      spans.add(TextSpan(text: text.substring(start, idx), style: base));
    }
    spans.add(TextSpan(text: text.substring(idx, idx + q.length), style: hit));
    start = idx + q.length;
  }
  if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
  return spans;
}
