import 'dart:async';

import 'sync_connectivity.dart';
import 'sync_event.dart';
import 'sync_operation.dart';
import 'sync_report.dart';
import 'sync_result.dart';
import 'sync_retry_policy.dart';
import 'sync_store.dart';

/// Processes one queued operation and returns its disposition.
typedef SyncProcessor = Future<SyncResult> Function(SyncOperation operation);

/// Clock callback used to make scheduling deterministic in tests.
typedef SyncClock = DateTime Function();

/// Coordinates a persistent, strict-FIFO offline operation queue.
///
/// Calls that access the store are serialized. A retry at the head of the queue
/// blocks newer work so server-side ordering remains deterministic.
final class OfflineSyncManager {
  /// Creates a manager.
  OfflineSyncManager({
    required SyncStore store,
    required SyncProcessor processor,
    SyncConnectivity connectivity = const AlwaysOnlineSyncConnectivity(),
    SyncRetryPolicy? retryPolicy,
    this.autoSync = true,
    this.disposeConnectivity = true,
    SyncClock? clock,
  })  : _store = store,
        _processor = processor,
        _connectivity = connectivity,
        _retryPolicy = retryPolicy ?? SyncRetryPolicy(),
        _clock = clock ?? DateTime.now;

  final SyncStore _store;
  final SyncProcessor _processor;
  final SyncConnectivity _connectivity;
  final SyncRetryPolicy _retryPolicy;
  final SyncClock _clock;
  final StreamController<SyncEvent> _events =
      StreamController<SyncEvent>.broadcast();

  Future<void> _tail = Future<void>.value();
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;
  bool _initialized = false;
  bool _disposed = false;

  /// Whether enqueue, reconnection, and timers trigger synchronization.
  final bool autoSync;

  /// Whether [dispose] also disposes the supplied connectivity source.
  final bool disposeConnectivity;

  /// Broadcast stream of queue lifecycle events.
  Stream<SyncEvent> get events => _events.stream;

  /// Initializes storage and connectivity listeners.
  Future<void> initialize({bool syncOnStart = true}) async {
    await _runSerial<void>(() async {
      _ensureNotDisposed();
      if (_initialized) {
        return;
      }
      await _store.initialize();
      _initialized = true;
      _connectivitySubscription = _connectivity.changes.distinct().listen(
        (bool online) {
          if (_disposed) {
            return;
          }
          if (!online) {
            _retryTimer?.cancel();
          } else if (autoSync) {
            unawaited(synchronize());
          }
        },
      );
    });

    if (syncOnStart && autoSync) {
      await synchronize();
    }
  }

  /// Builds and appends an operation to the end of the FIFO queue.
  Future<SyncOperation> enqueue({
    String? id,
    required String action,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final operation = SyncOperation.pending(
      id: id,
      action: action,
      payload: payload,
      createdAt: _clock(),
    );
    await enqueueOperation(operation);
    return operation;
  }

  /// Appends an existing operation to the end of the FIFO queue.
  Future<void> enqueueOperation(SyncOperation operation) async {
    await _runSerial<void>(() async {
      _ensureReady();
      final queue = await _store.readAll();
      if (queue.any((item) => item.id == operation.id)) {
        throw StateError(
            'An operation with ID ${operation.id} already exists.');
      }
      await _store.writeAll(<SyncOperation>[...queue, operation]);
      _emit(SyncEventType.enqueued, operation: operation);
    });

    if (autoSync) {
      unawaited(synchronize());
    }
  }

  /// Returns a snapshot of pending operations in FIFO order.
  Future<List<SyncOperation>> pendingOperations() {
    return _runSerial<List<SyncOperation>>(() async {
      _ensureReady();
      return _store.readAll();
    });
  }

  /// Removes a queued operation by ID and reports whether it existed.
  Future<bool> remove(String id) {
    return _runSerial<bool>(() async {
      _ensureReady();
      final queue = await _store.readAll();
      final remaining = queue.where((item) => item.id != id).toList();
      if (remaining.length == queue.length) {
        return false;
      }
      await _store.writeAll(remaining);
      return true;
    });
  }

  /// Removes all pending operations.
  Future<void> clear() {
    return _runSerial<void>(() async {
      _ensureReady();
      _retryTimer?.cancel();
      await _store.writeAll(const <SyncOperation>[]);
    });
  }

  /// Runs one serialized synchronization pass.
  Future<SyncReport> synchronize() {
    return _runSerial<SyncReport>(() async {
      _ensureReady();
      _retryTimer?.cancel();

      var queue = await _store.readAll();
      if (!await _connectivity.isOnline()) {
        _emit(SyncEventType.pausedOffline);
        return SyncReport(
          attempted: 0,
          succeeded: 0,
          retried: 0,
          discarded: 0,
          failedPermanently: 0,
          pending: queue.length,
          skippedOffline: true,
        );
      }

      var attempted = 0;
      var succeeded = 0;
      var retried = 0;
      var discarded = 0;
      var failedPermanently = 0;

      while (queue.isNotEmpty) {
        final operation = queue.first;
        final now = _clock().toUtc();
        final nextAttemptAt = operation.nextAttemptAt;
        if (nextAttemptAt != null && nextAttemptAt.isAfter(now)) {
          _scheduleRetry(nextAttemptAt);
          break;
        }

        attempted += 1;
        _emit(SyncEventType.processing, operation: operation);

        SyncResult result;
        try {
          result = await _processor(operation);
        } on Object catch (error) {
          result = SyncResult.retry(reason: error.toString());
        }

        switch (result.disposition) {
          case SyncDisposition.success:
            queue = queue.sublist(1);
            await _store.writeAll(queue);
            succeeded += 1;
            _emit(
              SyncEventType.succeeded,
              operation: operation,
              message: result.reason,
            );
          case SyncDisposition.discard:
            queue = queue.sublist(1);
            await _store.writeAll(queue);
            discarded += 1;
            _emit(
              SyncEventType.discarded,
              operation: operation,
              message: result.reason,
            );
          case SyncDisposition.retry:
            final attempts = operation.attemptCount + 1;
            if (!_retryPolicy.canRetryAfter(attempts)) {
              queue = queue.sublist(1);
              await _store.writeAll(queue);
              failedPermanently += 1;
              _emit(
                SyncEventType.failedPermanently,
                operation: operation.copyWith(attemptCount: attempts),
                message: result.reason,
              );
              continue;
            }

            final delay =
                result.retryAfter ?? _retryPolicy.delayAfter(attempts);
            if (delay.isNegative) {
              throw StateError('A processor returned a negative retry delay.');
            }
            final retryAt = _clock().toUtc().add(delay);
            final updated = operation.copyWith(
              attemptCount: attempts,
              nextAttemptAt: retryAt,
            );
            queue = <SyncOperation>[updated, ...queue.skip(1)];
            await _store.writeAll(queue);
            retried += 1;
            _emit(
              SyncEventType.retryScheduled,
              operation: updated,
              message: result.reason,
              nextAttemptAt: retryAt,
            );
            _scheduleRetry(retryAt);
            return SyncReport(
              attempted: attempted,
              succeeded: succeeded,
              retried: retried,
              discarded: discarded,
              failedPermanently: failedPermanently,
              pending: queue.length,
              skippedOffline: false,
            );
        }
      }

      return SyncReport(
        attempted: attempted,
        succeeded: succeeded,
        retried: retried,
        discarded: discarded,
        failedPermanently: failedPermanently,
        pending: queue.length,
        skippedOffline: false,
      );
    });
  }

  /// Cancels timers, closes storage, and releases event resources.
  Future<void> dispose() {
    return _runSerial<void>(() async {
      if (_disposed) {
        return;
      }
      _disposed = true;
      _retryTimer?.cancel();
      await _connectivitySubscription?.cancel();
      if (_initialized) {
        await _store.close();
      }
      if (disposeConnectivity) {
        await _connectivity.dispose();
      }
      await _events.close();
    });
  }

  Future<T> _runSerial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _scheduleRetry(DateTime retryAt) {
    if (!autoSync || _disposed) {
      return;
    }
    _retryTimer?.cancel();
    final delay = retryAt.difference(_clock().toUtc());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_disposed) {
        unawaited(synchronize());
      }
    });
  }

  void _emit(
    SyncEventType type, {
    SyncOperation? operation,
    String? message,
    DateTime? nextAttemptAt,
  }) {
    if (_events.isClosed) {
      return;
    }
    _events.add(
      SyncEvent(
        type: type,
        timestamp: _clock().toUtc(),
        operation: operation,
        message: message,
        nextAttemptAt: nextAttemptAt,
      ),
    );
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('Call initialize() before using OfflineSyncManager.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('OfflineSyncManager has been disposed.');
    }
  }
}
