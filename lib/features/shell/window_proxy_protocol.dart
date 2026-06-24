import 'dart:convert';
import 'dart:typed_data';

/// Wire protocol for the detached-window proxy bridge (ADR 0020, Model 2).
///
/// A detached window runs in its own Flutter engine/isolate and cannot share the
/// live [SshSession]; it only renders and proxies terminal I/O to the main window
/// over `WindowMethodChannel` using these serialized messages. This file is pure
/// Dart (no Flutter, no platform channels) so the codec is unit-testable in
/// isolation; the transport is wired separately.
///
/// Encoding is a JSON envelope `{ "v": <version>, "type": <name>, ... }`. Byte
/// payloads are base64-encoded. Decoding is defensive: any malformed or
/// future-version message decodes to [UnknownMessage] rather than throwing, so a
/// bad frame can never crash the main isolate (ADR 0015 in spirit).
const int kWindowProtocolVersion = 1;

sealed class WindowMessage {
  const WindowMessage();

  Map<String, Object?> _payload();

  String encode() =>
      jsonEncode(<String, Object?>{'v': kWindowProtocolVersion, ..._payload()});
}

// --- main window -> detached window ---

/// Terminal stdout bytes to render.
class OutputMessage extends WindowMessage {
  final Uint8List data;
  OutputMessage(this.data);
  @override
  Map<String, Object?> _payload() => {
    'type': 'output',
    'data': base64Encode(data),
  };
}

/// Scrollback replay sent once when the window opens.
class BacklogMessage extends WindowMessage {
  final Uint8List data;
  BacklogMessage(this.data);
  @override
  Map<String, Object?> _payload() => {
    'type': 'backlog',
    'data': base64Encode(data),
  };
}

/// Connection status (`ready`/`error`/`closed`/...).
class StatusMessage extends WindowMessage {
  final String status;
  const StatusMessage(this.status);
  @override
  Map<String, Object?> _payload() => {'type': 'status', 'status': status};
}

/// The proxied session has closed.
class ClosedMessage extends WindowMessage {
  const ClosedMessage();
  @override
  Map<String, Object?> _payload() => {'type': 'closed'};
}

// --- detached window -> main window ---

/// Terminal stdin bytes typed in the detached window.
class InputMessage extends WindowMessage {
  final Uint8List data;
  InputMessage(this.data);
  @override
  Map<String, Object?> _payload() => {
    'type': 'input',
    'data': base64Encode(data),
  };
}

/// The detached window's terminal resized.
class ResizeMessage extends WindowMessage {
  final int cols, rows, pixelWidth, pixelHeight;
  const ResizeMessage(this.cols, this.rows, this.pixelWidth, this.pixelHeight);
  @override
  Map<String, Object?> _payload() => {
    'type': 'resize',
    'cols': cols,
    'rows': rows,
    'pw': pixelWidth,
    'ph': pixelHeight,
  };
}

/// The user closed the detached window. [keepSession] true → re-dock into the
/// main window; false → close the underlying session.
class RequestCloseMessage extends WindowMessage {
  final bool keepSession;
  const RequestCloseMessage({required this.keepSession});
  @override
  Map<String, Object?> _payload() => {
    'type': 'requestClose',
    'keepSession': keepSession,
  };
}

/// The user asked to re-dock the detached tab into the main window.
class RedockRequestedMessage extends WindowMessage {
  final String tabId;
  const RedockRequestedMessage(this.tabId);
  @override
  Map<String, Object?> _payload() => {
    'type': 'redockRequested',
    'tabId': tabId,
  };
}

/// A frame that could not be understood (corrupt or from a newer protocol).
class UnknownMessage extends WindowMessage {
  final String raw;
  const UnknownMessage(this.raw);
  @override
  Map<String, Object?> _payload() => {'type': 'unknown'};
}

Uint8List _bytes(Object? v) => v is String ? base64Decode(v) : Uint8List(0);

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

/// Decode a wire frame. Never throws: malformed input → [UnknownMessage].
WindowMessage decodeWindowMessage(String raw) {
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return UnknownMessage(raw);
    switch (m['type']) {
      case 'output':
        return OutputMessage(_bytes(m['data']));
      case 'backlog':
        return BacklogMessage(_bytes(m['data']));
      case 'status':
        return StatusMessage('${m['status']}');
      case 'closed':
        return const ClosedMessage();
      case 'input':
        return InputMessage(_bytes(m['data']));
      case 'resize':
        return ResizeMessage(
          _int(m['cols']),
          _int(m['rows']),
          _int(m['pw']),
          _int(m['ph']),
        );
      case 'requestClose':
        return RequestCloseMessage(keepSession: m['keepSession'] == true);
      case 'redockRequested':
        return RedockRequestedMessage('${m['tabId']}');
      default:
        return UnknownMessage(raw);
    }
  } catch (_) {
    return UnknownMessage(raw);
  }
}
