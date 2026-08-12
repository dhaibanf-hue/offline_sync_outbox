import 'sync_operation.dart';

/// Persistence contract used by an offline sync manager.
///
/// Store implementations must preserve list order because the manager uses
/// strict FIFO processing.
abstract interface class SyncStore {
  /// Prepares the store for reads and writes.
  Future<void> initialize();

  /// Reads the entire queue in FIFO order.
  Future<List<SyncOperation>> readAll();

  /// Atomically replaces the queue when the backing store supports it.
  Future<void> writeAll(List<SyncOperation> operations);

  /// Releases resources held by the store.
  Future<void> close();
}

/// Wraps persistence failures with store-specific context.
final class SyncStoreException implements Exception {
  /// Creates a store exception.
  const SyncStoreException(this.message, {this.cause});

  /// Human-readable failure context.
  final String message;

  /// Original error, when available.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SyncStoreException: $message'
      : 'SyncStoreException: $message Cause: $cause';
}
