# offline_sync_outbox

[![pub package](https://img.shields.io/pub/v/offline_sync_outbox.svg)](https://pub.dev/packages/offline_sync_outbox)
[![CI](https://github.com/dhaibanf-hue/offline_sync_outbox/actions/workflows/ci.yml/badge.svg)](https://github.com/dhaibanf-hue/offline_sync_outbox/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A lightweight offline-first operation queue for Dart and Flutter. It keeps API
mutations in strict FIFO order, persists them as JSON, resumes when connectivity
returns, and applies configurable exponential backoff when requests fail.

## Why use it?

Mobile connections disappear at inconvenient moments. UI code should not need to
know whether a mutation was sent immediately, queued for later, or retried after a
temporary server failure. `offline_sync_outbox` isolates that responsibility
behind a small processor and storage abstraction.

## Features

- Strict FIFO processing for deterministic server-side ordering.
- Durable, atomic-style JSON file persistence for Dart IO platforms.
- In-memory store for tests and ephemeral workflows.
- Configurable exponential backoff and maximum attempt count.
- Optional server-directed retry delays.
- Automatic resume through a pluggable connectivity stream.
- Serialized store access, including concurrent enqueue calls.
- Duplicate operation ID protection.
- Lifecycle events and per-pass synchronization reports.
- Zero runtime package dependencies.

## Installation

For Flutter:

```console
flutter pub add offline_sync_outbox
```

For Dart:

```console
dart pub add offline_sync_outbox
```

## Quick start

```dart
final sync = OfflineSyncManager(
  store: JsonFileSyncStore('sync_queue.json'),
  processor: (op) async => sendToApi(op)
      ? const SyncResult.success()
      : const SyncResult.retry(),
);
await sync.initialize();
await sync.enqueue(action: 'create_order', payload: {'orderId': 42});
```

`sendToApi` represents your HTTP, gRPC, or repository-layer call. Return
`SyncResult.success()` after the server accepts the mutation,
`SyncResult.retry()` for temporary failures, or `SyncResult.discard()` for
permanent validation failures.

## Persistent storage

Pass an application-owned file path to `JsonFileSyncStore`. In Flutter, resolve
that path with the platform storage solution your app already uses. The store
writes a temporary file and retains a backup while replacing the live queue.

```dart
final store = JsonFileSyncStore('/app-data/offline-queue.json');
```

`JsonFileSyncStore` supports Dart IO platforms: Android, iOS, Windows, macOS,
Linux, and server-side Dart. For Flutter Web, implement `SyncStore` with IndexedDB
or another browser persistence layer.

Only JSON-encodable values should be placed in an operation payload. Create one
manager per persistent store path.

## Connectivity

The default connectivity source is always online. Adapt any connectivity package
or application service by implementing three members:

```dart
final class AppConnectivity implements SyncConnectivity {
  AppConnectivity(this.service);

  final NetworkService service;

  @override
  Stream<bool> get changes => service.onlineChanges;

  @override
  Future<bool> isOnline() => service.isOnline();

  @override
  Future<void> dispose() async {}
}
```

When the stream emits `true`, the manager automatically starts a pass if
`autoSync` is enabled.

## Retries

```dart
final policy = SyncRetryPolicy(
  maxAttempts: 6,
  initialDelay: const Duration(seconds: 2),
  maxDelay: const Duration(minutes: 2),
  multiplier: 2,
);
```

A failed head operation blocks newer operations until it succeeds, is discarded,
or exhausts its retry budget. This head-of-line behavior is deliberate: it avoids
reordering related mutations such as create, update, then delete.

Processors can override the calculated delay, for example after an HTTP 429:

```dart
return const SyncResult.retry(
  reason: 'rate limited',
  retryAfter: Duration(seconds: 30),
);
```

Unhandled processor exceptions are converted into retry results automatically.

## Observability

```dart
sync.events.listen((event) {
  print('${event.type}: ${event.operation?.id}');
});

final report = await sync.synchronize();
print('synced=${report.succeeded}, pending=${report.pending}');
```

## Lifecycle

Call `initialize()` before queue access and `dispose()` when the manager is no
longer needed. By default, disposing the manager also disposes its connectivity
source. Set `disposeConnectivity: false` when that source is shared.

## Architecture

The package separates policy from infrastructure:

- `OfflineSyncManager` serializes mutations and controls the FIFO loop.
- `SyncStore` owns persistence; JSON and memory implementations are included.
- `SyncProcessor` maps application-specific API behavior to a `SyncResult`.
- `SyncConnectivity` supplies online state without coupling to a plugin.
- `SyncRetryPolicy` calculates bounded exponential delays.

See [`example/offline_sync_outbox_example.dart`](example/offline_sync_outbox_example.dart)
for a complete runnable example.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for
the local validation commands.

## License

MIT. See [LICENSE](LICENSE).
