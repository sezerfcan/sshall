import 'dart:typed_data';
import 'ssh_messages.dart';

/// The terminal-facing contract a [TerminalSessionController] consumes. Lets a
/// container exec session (Docker, Faz 2 local) drive the same xterm pane as a
/// plain SSH shell. SshSession implements this; see ADR 0028.
abstract class TerminalSession {
  Stream<WorkerEvent> get events;
  WorkerEvent? get currentLifecycle;
  Uint8List takeOutputBacklog();
  void sendInput(Uint8List data);
  void resize(int w, int h, int pw, int ph);
  void decideHostKey(bool accept);
  Future<void> close();
}
