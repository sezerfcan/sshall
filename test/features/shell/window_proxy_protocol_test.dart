import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sshall/features/shell/window_proxy_protocol.dart';

void main() {
  T roundTrip<T extends WindowMessage>(WindowMessage m) {
    final decoded = decodeWindowMessage(m.encode());
    return decoded as T;
  }

  group('encode/decode round-trips', () {
    test('output carries raw bytes intact', () {
      final m = OutputMessage(Uint8List.fromList([0, 27, 91, 65, 255]));
      final r = roundTrip<OutputMessage>(m);
      expect(r.data, [0, 27, 91, 65, 255]);
    });

    test('backlog carries raw bytes intact', () {
      final m = BacklogMessage(Uint8List.fromList([1, 2, 3]));
      expect(roundTrip<BacklogMessage>(m).data, [1, 2, 3]);
    });

    test('input carries raw bytes intact', () {
      final m = InputMessage(Uint8List.fromList([108, 115, 10]));
      expect(roundTrip<InputMessage>(m).data, [108, 115, 10]);
    });

    test('status carries the status string', () {
      expect(
        roundTrip<StatusMessage>(const StatusMessage('error')).status,
        'error',
      );
    });

    test('resize carries all four dimensions', () {
      final r = roundTrip<ResizeMessage>(const ResizeMessage(80, 24, 640, 384));
      expect([r.cols, r.rows, r.pixelWidth, r.pixelHeight], [80, 24, 640, 384]);
    });

    test('requestClose carries the keepSession flag', () {
      expect(
        roundTrip<RequestCloseMessage>(
          const RequestCloseMessage(keepSession: true),
        ).keepSession,
        isTrue,
      );
    });

    test('redockRequested carries the tab id', () {
      expect(
        roundTrip<RedockRequestedMessage>(
          const RedockRequestedMessage('t3'),
        ).tabId,
        't3',
      );
    });

    test('closed survives a round-trip', () {
      expect(
        roundTrip<ClosedMessage>(const ClosedMessage()),
        isA<ClosedMessage>(),
      );
    });
  });

  group('defensive decoding (must never throw)', () {
    test('garbage decodes to UnknownMessage', () {
      expect(decodeWindowMessage('not json {'), isA<UnknownMessage>());
    });

    test('a JSON object with no known type decodes to UnknownMessage', () {
      expect(decodeWindowMessage('{"type":"wat"}'), isA<UnknownMessage>());
    });

    test('a non-object JSON decodes to UnknownMessage', () {
      expect(decodeWindowMessage('[1,2,3]'), isA<UnknownMessage>());
    });

    test('every encoded message includes the protocol version', () {
      expect(
        OutputMessage(
          Uint8List(0),
        ).encode().contains('"v":$kWindowProtocolVersion'),
        isTrue,
      );
    });
  });
}
