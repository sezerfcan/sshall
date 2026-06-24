import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/services/sftp/transfer_rate_meter.dart';

void main() {
  group('TransferRateMeter', () {
    test('null rate until two samples', () {
      final m = TransferRateMeter();
      expect(m.bytesPerSec, isNull);
      m.sample(0, at: Duration.zero);
      expect(m.bytesPerSec, isNull);
    });

    test('computes bytes/sec across two samples', () {
      final m = TransferRateMeter();
      m.sample(0, at: Duration.zero);
      m.sample(1000000, at: const Duration(seconds: 1));
      expect(m.bytesPerSec, closeTo(1000000, 1));
    });

    test('window smooths a single burst (does not spike to the jump rate)', () {
      // 1 MB/s steady for 3s, then a sudden +5MB jump in the last 100ms. With a
      // 3s window the slope across the window stays far below the instantaneous
      // jump rate (which would be 50 MB/s for that one tick).
      final m = TransferRateMeter(window: const Duration(seconds: 3));
      m.sample(0, at: Duration.zero);
      m.sample(1000000, at: const Duration(seconds: 1));
      m.sample(2000000, at: const Duration(seconds: 2));
      m.sample(3000000, at: const Duration(seconds: 3));
      m.sample(8000000, at: const Duration(milliseconds: 3100));
      // Window slope ~ (8MB-0)/3.1s ≈ 2.58 MB/s, nowhere near 50 MB/s.
      expect(m.bytesPerSec, lessThan(3000000));
    });

    test('old samples are evicted past the window', () {
      final m = TransferRateMeter(window: const Duration(seconds: 2));
      m.sample(0, at: Duration.zero);
      m.sample(1000000, at: const Duration(seconds: 5));
      // 1 MB/s steady from t=5..t=7 inside the window.
      m.sample(2000000, at: const Duration(seconds: 6));
      m.sample(3000000, at: const Duration(seconds: 7));
      // The t=0 baseline is evicted; slope reflects only the recent window.
      expect(m.bytesPerSec, closeTo(1000000, 50000));
    });

    test('ETA = remaining / rate', () {
      final m = TransferRateMeter();
      m.sample(0, at: Duration.zero);
      m.sample(2000000, at: const Duration(seconds: 1)); // 2 MB/s
      final eta = m.etaFor(10000000); // done=2MB, remaining=8MB -> ~4s
      expect(eta, isNotNull);
      expect(eta!.inMilliseconds, closeTo(4000, 50));
    });

    test('ETA null when rate is zero (stalled)', () {
      final m = TransferRateMeter();
      m.sample(1000, at: Duration.zero);
      m.sample(1000, at: const Duration(seconds: 1)); // no progress -> rate 0
      expect(m.bytesPerSec, 0);
      expect(m.etaFor(5000), isNull);
    });

    test('ignores regressing / out-of-order samples', () {
      final m = TransferRateMeter();
      m.sample(1000, at: const Duration(seconds: 1));
      m.sample(500, at: const Duration(seconds: 2)); // regress -> ignored
      m.sample(
        3000,
        at: const Duration(milliseconds: 500),
      ); // earlier -> ignored
      m.sample(3000, at: const Duration(seconds: 3));
      // Only the first and last valid samples count: (3000-1000)/2s = 1000 B/s.
      expect(m.bytesPerSec, closeTo(1000, 1));
    });
  });
}
