/// Pure, clock-injectable byte-rate + ETA estimator for a transfer (D7).
///
/// Fed monotonically-increasing "total bytes done" samples (each with an
/// injected timestamp so there is no dependency on the wall clock — unit-tested
/// deterministically). The rate is the slope across a short sliding [window],
/// which smooths out the burstiness of individual [TransferProgress] events; a
/// single big jump does not spike the reported speed.
///
/// Used by the transfer queue panel to show speed/ETA per active file and per
/// batch. No Flutter, no timers — see ADR 0037 D7.
class TransferRateMeter {
  TransferRateMeter({this.window = const Duration(seconds: 3)});

  /// Sliding window over which the slope (bytes/sec) is computed. Older samples
  /// are evicted so a transient stall or burst fades out within [window].
  final Duration window;

  final List<({Duration at, int bytes})> _samples = [];

  /// Record [totalBytesDone] (a cumulative counter, never decreasing) observed
  /// at time [at] (a monotonic offset, e.g. from a Stopwatch or an injected
  /// fake). Out-of-order or regressing samples are ignored so a late event can
  /// never make the rate negative.
  void sample(int totalBytesDone, {required Duration at}) {
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      if (at < last.at || totalBytesDone < last.bytes) return;
    }
    _samples.add((at: at, bytes: totalBytesDone));
    final cutoff = at - window;
    // Keep one sample at/just-before the cutoff so the window has a baseline,
    // then drop anything older.
    while (_samples.length > 2 && _samples[1].at <= cutoff) {
      _samples.removeAt(0);
    }
  }

  /// Smoothed throughput in bytes/sec across the window, or null until there are
  /// two distinct-time samples to draw a slope from.
  double? get bytesPerSec {
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;
    final dt = (last.at - first.at).inMicroseconds;
    if (dt <= 0) return null;
    final dBytes = last.bytes - first.bytes;
    if (dBytes <= 0) return 0;
    return dBytes * Duration.microsecondsPerSecond / dt;
  }

  /// Estimated time to move the remaining ([totalBytes] − last sample) bytes at
  /// the current [bytesPerSec]. Null when the rate is unknown or zero, or when
  /// already complete.
  Duration? etaFor(int totalBytes) {
    final rate = bytesPerSec;
    if (rate == null || rate <= 0) return null;
    final done = _samples.isEmpty ? 0 : _samples.last.bytes;
    final remaining = totalBytes - done;
    if (remaining <= 0) return Duration.zero;
    final seconds = remaining / rate;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}
