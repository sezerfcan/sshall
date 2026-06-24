import 'package:url_launcher/url_launcher.dart';

/// Opens a local file in the OS default application. Seam so the editor launch
/// can be faked in tests (the real impl talks to the platform shell).
abstract interface class FileOpener {
  /// Returns true if the OS accepted the open request.
  Future<bool> open(String path);
}

class UrlLauncherFileOpener implements FileOpener {
  const UrlLauncherFileOpener();
  @override
  Future<bool> open(String path) =>
      launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
}
