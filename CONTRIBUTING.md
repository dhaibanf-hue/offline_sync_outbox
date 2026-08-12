# Contributing

Thanks for helping improve `offline_sync_manager`.

## Local checks

```console
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Please add tests for behavior changes, keep the public API documented, and avoid
runtime dependencies unless the same behavior cannot be expressed through an
adapter interface.

## Pull requests

Keep each pull request focused. Explain the user-facing impact, document any
ordering or persistence tradeoffs, and update `CHANGELOG.md` when appropriate.
