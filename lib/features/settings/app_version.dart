import 'package:package_info_plus/package_info_plus.dart';

/// App name shown alongside the version (kept here so the About card and the
/// title-bar badge use the same brand string).
const String kAppName = 'sshall';

/// Fallback version string kept in sync with pubspec's `version:` field. Used
/// only if [PackageInfo.fromPlatform] ever fails (it is mocked in tests via
/// `PackageInfo.setMockInitialValues`). Centralizing it here means the About
/// card and the title-bar badge never carry two drifting hard-coded strings
/// (ADR 0038 D9 fallback).
const String kAppVersion = '1.0.0';

/// Resolves the runtime version label, e.g. `sshall 1.0.0 (build 1)` (ADR 0038
/// D9). Read by BOTH the About card and the title-bar version badge so the two
/// can never drift again. On any failure it degrades to the [kAppVersion]
/// constant rather than throwing.
Future<String> appVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.isEmpty ? kAppVersion : info.version;
    final build = info.buildNumber;
    return build.isEmpty
        ? '$kAppName $version'
        : '$kAppName $version (build $build)';
  } catch (_) {
    return '$kAppName $kAppVersion';
  }
}

/// A compact version label for the title-bar badge, e.g. `v1.0.0` (ADR 0038
/// D9). Same runtime source as [appVersionLabel].
Future<String> appVersionBadge() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.isEmpty ? kAppVersion : info.version;
    return 'v$version';
  } catch (_) {
    return 'v$kAppVersion';
  }
}
