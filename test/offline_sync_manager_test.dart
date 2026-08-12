import 'package:offline_sync_outbox/offline_sync_outbox.dart';
import 'package:test/test.dart';

void main() {
  group('OfflineSyncManager', () {
    test('processes successful operations in FIFO order', () async {
      final processed = <String>[];
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        processor: (operation) async {
          processed.add(operation.id);
          return const SyncResult.success();
        },
      );
      await manager.initialize();
      await manager.enqueue(id: 'one', action: 'first');
      await manager.enqueue(id: 'two', action: 'second');

      final report = await manager.synchronize();

      expect(processed, <String>['one', 'two']);
      expect(report.attempted, 2);
      expect(report.succeeded, 2);
      expect(report.isQueueEmpty, isTrue);
      await manager.dispose();
    });

    test('strict FIFO blocks newer work while the head retries', () async {
      var firstAttempts = 0;
      final processed = <String>[];
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        retryPolicy: SyncRetryPolicy(initialDelay: Duration.zero),
        processor: (operation) async {
          processed.add(operation.id);
          if (operation.id == 'one' && firstAttempts++ == 0) {
            return const SyncResult.retry(retryAfter: Duration.zero);
          }
          return const SyncResult.success();
        },
      );
      await manager.initialize();
      await manager.enqueue(id: 'one', action: 'first');
      await manager.enqueue(id: 'two', action: 'second');

      final firstReport = await manager.synchronize();
      final secondReport = await manager.synchronize();

      expect(firstReport.retried, 1);
      expect(firstReport.pending, 2);
      expect(secondReport.succeeded, 2);
      expect(processed, <String>['one', 'one', 'two']);
      await manager.dispose();
    });

    test('processor exceptions consume the retry budget', () async {
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        retryPolicy: SyncRetryPolicy(
          maxAttempts: 2,
          initialDelay: Duration.zero,
        ),
        processor: (_) async => throw StateError('network failure'),
      );
      await manager.initialize();
      await manager.enqueue(id: 'one', action: 'fails');

      final firstReport = await manager.synchronize();
      final secondReport = await manager.synchronize();

      expect(firstReport.retried, 1);
      expect(secondReport.failedPermanently, 1);
      expect(secondReport.pending, 0);
      await manager.dispose();
    });

    test('discarded operations do not block later work', () async {
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        processor: (operation) async => operation.id == 'invalid'
            ? const SyncResult.discard(reason: 'invalid payload')
            : const SyncResult.success(),
      );
      await manager.initialize();
      await manager.enqueue(id: 'invalid', action: 'first');
      await manager.enqueue(id: 'valid', action: 'second');

      final report = await manager.synchronize();

      expect(report.discarded, 1);
      expect(report.succeeded, 1);
      expect(report.pending, 0);
      await manager.dispose();
    });

    test('offline passes leave the queue untouched', () async {
      final connectivity = ManualSyncConnectivity(isOnline: false);
      var processorCalls = 0;
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        connectivity: connectivity,
        autoSync: false,
        processor: (_) async {
          processorCalls += 1;
          return const SyncResult.success();
        },
      );
      await manager.initialize();
      await manager.enqueue(id: 'one', action: 'waiting');

      final report = await manager.synchronize();

      expect(report.skippedOffline, isTrue);
      expect(report.pending, 1);
      expect(processorCalls, 0);
      await manager.dispose();
    });

    test('concurrent enqueues are serialized', () async {
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        processor: (_) async => const SyncResult.success(),
      );
      await manager.initialize();

      await Future.wait(<Future<SyncOperation>>[
        manager.enqueue(id: 'one', action: 'first'),
        manager.enqueue(id: 'two', action: 'second'),
        manager.enqueue(id: 'three', action: 'third'),
      ]);
      final pending = await manager.pendingOperations();

      expect(
        pending.map((operation) => operation.id),
        <String>['one', 'two', 'three'],
      );
      await manager.dispose();
    });

    test('duplicate operation IDs are rejected', () async {
      final manager = OfflineSyncManager(
        store: MemorySyncStore(),
        autoSync: false,
        processor: (_) async => const SyncResult.success(),
      );
      await manager.initialize();
      await manager.enqueue(id: 'duplicate', action: 'first');

      expect(
        () => manager.enqueue(id: 'duplicate', action: 'second'),
        throwsStateError,
      );
      await manager.dispose();
    });
  });
}
