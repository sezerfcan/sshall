import 'connection.dart';
import 'identity.dart';
import 'host_key_pin.dart';
import 'folder.dart';

class VaultData {
  final List<Connection> connections;
  final List<Folder> folders;
  final List<Identity> identities;
  final List<HostKeyPin> pins;

  const VaultData({
    required this.connections,
    required this.folders,
    required this.identities,
    required this.pins,
  });

  factory VaultData.empty() => const VaultData(
      connections: [], folders: [], identities: [], pins: []);

  /// Returns a copy with the given fields replaced; omitted fields keep their
  /// existing (same-reference) value. Lets call sites mutate one list without
  /// re-listing the unchanged three.
  VaultData copyWith({
    List<Connection>? connections,
    List<Folder>? folders,
    List<Identity>? identities,
    List<HostKeyPin>? pins,
  }) =>
      VaultData(
        connections: connections ?? this.connections,
        folders: folders ?? this.folders,
        identities: identities ?? this.identities,
        pins: pins ?? this.pins,
      );

  Map<String, dynamic> toJson() => {
        'connections': connections.map((c) => c.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
        'identities': identities.map((i) => i.toJson()).toList(),
        'pins': pins.map((p) => p.toJson()).toList(),
      };

  factory VaultData.fromJson(Map<String, dynamic> j) => VaultData(
        connections: _parseList(j['connections'], Connection.fromJson),
        // Backward-compatible: old vaults have no `folders` key.
        folders: _parseList(j['folders'], Folder.fromJson),
        identities: _parseList(j['identities'], Identity.fromJson),
        pins: _parseList(j['pins'], HostKeyPin.fromJson),
      );

  /// Defensively parses a JSON list into model objects.
  ///
  /// A single corrupt or forward-schema record must NOT crash the whole vault
  /// unlock (which would make every saved connection unreachable). So:
  /// - a missing/non-list value yields an empty list (not a cast error);
  /// - each element is parsed in isolation; a non-map element or one that throws
  ///   (missing required field, unknown enum, wrong type) is skipped, and the
  ///   remaining good records are kept.
  static List<T> _parseList<T>(
      Object? raw, T Function(Map<String, dynamic>) parse) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final e in raw) {
      if (e is! Map) continue; // not a record at all -> skip.
      try {
        out.add(parse(Map<String, dynamic>.from(e)));
      } catch (_) {
        // Corrupt/forward-schema record: drop it, don't take down the vault.
        continue;
      }
    }
    return out;
  }
}
