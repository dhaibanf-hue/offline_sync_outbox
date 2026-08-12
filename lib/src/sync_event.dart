import 'sync_operation.dart';

/// Lifecycle event emitted by the sync manager.
enum SyncEventType {
  /// An operation entered the queue.
  enqueued,

  /// Processing of an operation started.
  processing,

  /// An operation completed successfully.
  succeeded,

  /// An operation was retained for a later retry.
  retryScheduled,

  /// A processor intentionally discarded an operation.
  discarded,

  /// An operation exhausted its retry budget.
  failedPermanently,

  /// Synchronization was skipped while offline.
  pausedOffline,
}

/// Diagnostic information about a queue lifecycle transition.
final class SyncEvent {
  /// Creates an event.
  const SyncEvent({
    required this.type,
    required this.timestamp,
    this.operation,
    this.message,
    this.nextAttemptAt,
  });

  /// Kind of lifecycle transition.
  final SyncEventType type;

  /// UTC time at which the event occurred.
  final DateTime timestamp;

  /// Related operation, when the event targets a queue item.
  final SyncOperation? operation;

  /// Optional processor or error detail.
  final String? message;

  /// Scheduled retry time for [SyncEventType.retryScheduled].
  final DateTime? nextAttemptAt;
}
