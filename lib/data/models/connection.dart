const Object _sentinel = Object();

/// A saved connection (a node in the connection tree). The inheritable fields
/// [username]/[port]/[authRef] are nullable: null means "inherit from the
/// folder chain" (resolved by `resolve()` in data/resolve/connection_resolver.dart).
/// [host] is always connection-specific and never inherited.
class Connection {
  final String id;
  final String label;
  final String host;

  /// Parent folder id; null = root level.
  final String? folderId;

  /// Inheritable overrides. null = inherit from the folder chain.
  final String? username;
  final int? port;
  final String? authRef;

  /// Host-only tags (NOT inherited from folders).
  final List<String> tags;

  /// Sibling ordering (ascending).
  final int order;

  /// This host runs Docker; when true the sidebar shows its containers.
  final bool docker;

  /// Override for the docker binary/invocation (e.g. "sudo docker"); null = "docker".
  final String? dockerBinary;

  const Connection({
    required this.id,
    required this.label,
    required this.host,
    required this.folderId,
    required this.username,
    required this.port,
    required this.authRef,
    required this.tags,
    required this.order,
    this.docker = false,
    this.dockerBinary,
  });

  /// Returns a copy with the given fields replaced. For the nullable override
  /// fields (folderId/username/port/authRef), omitting the argument keeps the
  /// current value (sentinel), while passing `null` explicitly clears it to
  /// "inherit from the folder chain".
  Connection copyWith({
    String? label,
    String? host,
    Object? folderId = _sentinel,
    Object? username = _sentinel,
    Object? port = _sentinel,
    Object? authRef = _sentinel,
    List<String>? tags,
    int? order,
    bool? docker,
    Object? dockerBinary = _sentinel,
  }) =>
      Connection(
        id: id,
        label: label ?? this.label,
        host: host ?? this.host,
        folderId: identical(folderId, _sentinel) ? this.folderId : folderId as String?,
        username: identical(username, _sentinel) ? this.username : username as String?,
        port: identical(port, _sentinel) ? this.port : port as int?,
        authRef: identical(authRef, _sentinel) ? this.authRef : authRef as String?,
        tags: tags ?? this.tags,
        order: order ?? this.order,
        docker: docker ?? this.docker,
        dockerBinary: identical(dockerBinary, _sentinel)
            ? this.dockerBinary
            : dockerBinary as String?,
      );

  Connection withFolder(String? folderId) => copyWith(folderId: folderId);

  Connection withTags(List<String> tags) => copyWith(tags: tags);

  /// Replaces ALL three inheritable overrides wholesale (null = inherit).
  Connection withOverrides({
    required String? username,
    required int? port,
    required String? authRef,
  }) =>
      copyWith(username: username, port: port, authRef: authRef);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'folderId': folderId,
        'username': username,
        'port': port,
        'authRef': authRef,
        'tags': tags,
        'order': order,
        'docker': docker,
        'dockerBinary': dockerBinary,
      };

  factory Connection.fromJson(Map<String, dynamic> j) => Connection(
        id: j['id'] as String,
        label: j['label'] as String,
        host: j['host'] as String,
        folderId: j['folderId'] as String?,
        username: j['username'] as String?,
        port: j['port'] as int?,
        authRef: j['authRef'] as String?,
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
        order: (j['order'] as int?) ?? 0,
        docker: j['docker'] as bool? ?? false,
        dockerBinary: j['dockerBinary'] as String?,
      );
}
