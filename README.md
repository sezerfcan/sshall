# sshall

**A free, open-source, cross-platform SSH client built with Flutter.**

sshall aims to bring the best parts of paid SSH tools — a fast terminal, a tidy
connection manager, integrated SFTP, an encrypted key vault, and Docker access —
into a single, free, open-source desktop app.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)
![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B.svg)
![Release: none yet](https://img.shields.io/badge/release-none%20yet-lightgrey.svg)

> **Status:** Early development — **no released version yet.** There are no
> tagged releases or pre-built binaries available for download; for now, run it
> from source (see [Getting started](#getting-started)). The current build
> targets **macOS desktop**; additional platforms are a goal, not yet shipped.

## Features

**Terminal**
- Full-featured terminal powered by [`xterm`](https://pub.dev/packages/xterm)
  over [`dartssh2`](https://pub.dev/packages/dartssh2) and a local PTY.
- Tabs, resizable split panes, and pop-out (detached) terminal windows.
- Discoverable keyboard shortcuts with an in-app shortcuts reference.

**Connections & security**
- Connection manager with folders, tags, quick-connect, and recent targets.
- Host-key verification and pinning, with an explicit man-in-the-middle warning
  when a host key changes.

**SFTP**
- Dual-pane (local ⇄ remote) file browser with breadcrumb navigation.
- Drag-to-transfer with a transfer queue showing live rate and ETA.
- Remote file editing (open in your editor, auto-sync on save), `chmod`, and
  conflict handling.

**Vault & keys**
- Encrypted vault for identities (passwords / private keys), unlocked with a
  master secret.
- Built-in SSH key generation.
- Secrets are kept in the OS secure storage (macOS Keychain) via
  [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage).

**Docker**
- Connect to Docker hosts (local or over SSH), browse containers, and run shell
  sessions and file operations inside them.

**Experience**
- Multiple built-in themes (e.g. Tokyo Night) with a theme picker.
- Frameless, native-feeling window chrome on macOS.
- Self-explanatory UI: every meaningful control carries a tooltip, hint, or help
  affordance.

## Screenshots

_Coming soon._

## Tech stack

- **Framework:** Flutter (desktop), Dart SDK `^3.11.0`
- **State:** [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod)
- **SSH / terminal:** `dartssh2`, `xterm`, `flutter_pty`
- **Crypto:** `cryptography_plus`, `pointycastle`, `pinenacl`
- **Windowing:** `window_manager`, `desktop_multi_window`

## Getting started

There are no pre-built binaries yet — build and run from source:

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) on the stable channel
  (Dart SDK `^3.11.0` or newer)
- macOS with Xcode and CocoaPods (for the macOS desktop build)

### Run

```bash
git clone https://github.com/sezerfcan/sshall.git
cd sshall
flutter pub get
flutter run -d macos
```

### Tests

```bash
flutter test          # unit and widget tests
flutter analyze       # static analysis / lints
```

## Project structure

```
lib/
  app/         App wiring and providers
  core/        Small shared utilities
  data/        Models, folder tree, connection resolution, secure store
  features/    Feature modules (connect, connections, terminal, sftp,
               vault, shell, settings, docker, …)
  services/    SSH, SFTP, crypto, keygen, docker, storage
  theme/       Design tokens, themes, theme controller
  widgets/     Reusable UI building blocks
test/          Unit and widget tests mirroring lib/
integration_test/  Driver-based integration tests
macos/         macOS desktop runner
```

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
coding conventions, and the pull-request process.

## License

Released under the [MIT License](LICENSE).
