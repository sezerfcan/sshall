import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// A private key chosen by the user: its decoded PEM/OpenSSH [pem] text and the
/// source file's [name] (for display).
typedef PickedKey = ({String pem, String name});

/// Decodes raw key-file [bytes] into PEM/OpenSSH text.
///
/// PEM/OpenSSH key text is ASCII, but a file may carry a UTF-8 BOM or a comment
/// with a non-ASCII byte. Decoding as lenient UTF-8 (rather than treating each
/// raw byte as a code unit, as `String.fromCharCodes` would) avoids mangling
/// those bytes into a broken key. Pure and synchronous so it is unit-testable.
String decodeKeyBytes(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

/// Prompts the user to pick a private-key file and returns its decoded text +
/// name, or null if the picker was dismissed / no file was chosen.
///
/// Extracted from the connect and folder-defaults dialogs, which previously
/// duplicated this FilePicker + lenient-UTF-8 decode byte for byte.
Future<PickedKey?> pickPrivateKey() async {
  final res = await FilePicker.platform.pickFiles(withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.single;
  return (pem: decodeKeyBytes(f.bytes ?? const []), name: f.name);
}
