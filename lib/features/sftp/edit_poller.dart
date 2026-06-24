import 'dart:async';

/// Periodic ticker used to poll edited temp files for local saves. Seam so the
/// controller can be driven by a fake (manual tick) in tests.
abstract interface class EditPoller {
  void start(Duration interval, void Function() onTick);
  void stop();
}

class TimerEditPoller implements EditPoller {
  Timer? _timer;
  @override
  void start(Duration interval, void Function() onTick) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
