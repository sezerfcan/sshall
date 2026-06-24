import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared formatting + clipboard helpers for the vault identity / known-hosts
/// surfaces (ADR 0033 / D8). Pure string helpers are unit-testable.

/// Truncates a long fingerprint to "head…tail" for inline display while the
/// full value stays available via tooltip / detail (D2). Short values pass
/// through unchanged. Keeps the "SHA256:" label visible so the value is
/// recognizable as a fingerprint.
String shortFingerprint(String fp, {int head = 12, int tail = 6}) {
  if (fp.length <= head + tail + 1) return fp;
  return '${fp.substring(0, head)}…${fp.substring(fp.length - tail)}';
}

/// Copies [text] to the clipboard and shows a brief "Kopyalandı" confirmation
/// (D8). [label] names what was copied for the SnackBar.
Future<void> copyWithFeedback(
  BuildContext context,
  String text, {
  required String label,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$label kopyalandı'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Formats an epoch-ms timestamp as a short local date for the detail view's
/// "Oluşturulma" field. Returns "Bilinmiyor" when null (no creation date
/// recorded).
String formatCreatedAt(int? epochMs) {
  if (epochMs == null) return 'Bilinmiyor';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
