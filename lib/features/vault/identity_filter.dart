import '../../data/models/identity.dart';
import 'identity_view_model.dart';

/// Identity type filter for the vault list (ADR 0033 / D6).
enum IdentityTypeFilter { all, keys, passwords }

extension IdentityTypeFilterLabel on IdentityTypeFilter {
  String get label => switch (this) {
    IdentityTypeFilter.all => 'Tümü',
    IdentityTypeFilter.keys => 'Anahtarlar',
    IdentityTypeFilter.passwords => 'Parolalar',
  };
}

/// Pure identity filter (ADR 0033 / D6). Matches [query] against the label,
/// algorithm label, AND fingerprint (so a user can paste a server-reported
/// SHA256 and find the local key). [typeFilter] splits keys/passwords;
/// [unusedOnly] keeps only identities with zero usage.
///
/// [viewOf] supplies the derived [IdentityView] (algorithm + fingerprint);
/// [usage] maps identity id → reference count.
List<Identity> filterIdentities(
  List<Identity> all, {
  String query = '',
  IdentityTypeFilter typeFilter = IdentityTypeFilter.all,
  bool unusedOnly = false,
  required Map<String, int> usage,
  required IdentityView Function(Identity) viewOf,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final id in all)
      if (_matchesType(id, typeFilter) &&
          _matchesUsage(id, unusedOnly, usage) &&
          _matchesQuery(id, q, viewOf))
        id,
  ];
}

bool _matchesType(Identity id, IdentityTypeFilter f) => switch (f) {
  IdentityTypeFilter.all => true,
  IdentityTypeFilter.keys => id.type == IdentityType.privateKey,
  IdentityTypeFilter.passwords => id.type == IdentityType.password,
};

bool _matchesUsage(Identity id, bool unusedOnly, Map<String, int> usage) =>
    !unusedOnly || (usage[id.id] ?? 0) == 0;

bool _matchesQuery(
  Identity id,
  String q,
  IdentityView Function(Identity) viewOf,
) {
  if (q.isEmpty) return true;
  if (id.label.toLowerCase().contains(q)) return true;
  final view = viewOf(id);
  if (view.algorithmLabel.toLowerCase().contains(q)) return true;
  final fp = view.fingerprint;
  if (fp != null && fp.toLowerCase().contains(q)) return true;
  return false;
}
