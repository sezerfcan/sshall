import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/sftp/edit_poller.dart';

void main() {
  test('TimerEditPoller fires onTick every interval until stopped', () {
    fakeAsync((async) {
      var ticks = 0;
      final poller = TimerEditPoller();
      poller.start(const Duration(seconds: 1), () => ticks++);
      async.elapse(const Duration(seconds: 3));
      expect(ticks, 3);
      poller.stop();
      async.elapse(const Duration(seconds: 3));
      expect(ticks, 3); // no more ticks after stop
    });
  });
}
