import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/window_chrome.dart';

/// A fake [WindowChrome] seam (ADR 0039) that records its calls so the title
/// bar's OS-title mirror can be asserted without driving window_manager.
class _RecordingChrome implements WindowChrome {
  final List<String> titles = [];
  int drags = 0;
  int toggles = 0;

  @override
  Future<void> startDragging() async => drags++;

  @override
  Future<void> toggleMaximize() async => toggles++;

  @override
  Future<void> setTitle(String title) async => titles.add(title);

  @override
  Future<bool> isFullScreen() async => false;
}

void main() {
  group('WindowChrome.setTitle seam (ADR 0039 D1)', () {
    test('setTitle forwards the requested OS window title', () async {
      final chrome = _RecordingChrome();
      await chrome.setTitle('sshall — web.example.com');
      expect(chrome.titles, ['sshall — web.example.com']);
    });

    test('a fake seam records titles without driving window_manager', () async {
      final chrome = _RecordingChrome();
      await chrome.setTitle('sshall');
      await chrome.setTitle('sshall — db');
      expect(chrome.titles, ['sshall', 'sshall — db']);
      // The other seam members keep working independently.
      await chrome.startDragging();
      await chrome.toggleMaximize();
      expect(chrome.drags, 1);
      expect(chrome.toggles, 1);
    });
  });
}
