# Contributing to sshall

Thanks for your interest in contributing! This guide covers how to set up the
project, the conventions we follow, and how to get your changes merged.

## Getting started

1. **Fork** the repository and clone your fork.
2. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable
   channel, Dart SDK `^3.11.0` or newer).
3. Fetch dependencies and run the app:
   ```bash
   flutter pub get
   flutter run -d macos
   ```

## Development workflow

1. Create a branch off `main` for your change:
   ```bash
   git checkout -b feat/short-description
   ```
2. Make your change, keeping commits small and focused.
3. Make sure the project is green before opening a PR:
   ```bash
   flutter analyze     # must report no issues
   flutter test        # all tests must pass
   ```
4. Push your branch and open a pull request against `main`.

## Coding conventions

- **Language:** all code, comments, commit messages, and PR titles are in
  **English**.
- **Style:** follow the analyzer. Lints are configured in
  [`analysis_options.yaml`](analysis_options.yaml) (based on `flutter_lints`).
  Run `dart format .` before committing.
- **Architecture:** the app is organized by feature under `lib/features/`, with
  shared logic in `lib/services/`, `lib/data/`, and `lib/widgets/`. Put new code
  next to the feature it belongs to and reuse existing widgets and services.
- **Discoverability:** the UI should explain itself. When you add a control,
  give it a tooltip, hint, or help affordance — don't leave the user guessing.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/). Examples:

```
feat(sftp): show transfer ETA in the queue
fix(vault): unlock fails after app restart
refactor(shell): extract split-tree layout
test(connect): cover host-key mismatch dialog
```

## Tests

- Add or update tests for any behavior you change.
- Unit and widget tests live under `test/`, mirroring the `lib/` structure.
- Integration (driver) tests live under `integration_test/`.

## Pull requests

- Keep PRs scoped to a single concern; smaller PRs are reviewed faster.
- Describe **what** changed and **why**, and link any related issue.
- Confirm `flutter analyze` and `flutter test` pass.
- Include screenshots or a short clip for user-facing UI changes.

## Reporting bugs & requesting features

Open an issue with clear reproduction steps (for bugs) or the problem you're
trying to solve (for features). Include your OS and Flutter version
(`flutter --version`) when relevant.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
