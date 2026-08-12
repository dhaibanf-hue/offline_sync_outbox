/// Aggregate result of one synchronization pass.
final class SyncReport {
  /// Creates a report.
  const SyncReport({
    required this.attempted,
    required this.succeeded,
    required this.retried,
    required this.discarded,
    required this.failedPermanently,
    required this.pending,
    required this.skippedOffline,
  });

  /// Number of processor calls made.
  final int attempted;

  /// Number of successful operations removed.
  final int succeeded;

  /// Number of operations retained for retry.
  final int retried;

  /// Number of operations intentionally discarded.
  final int discarded;

  /// Number of operations removed after exhausting retries.
  final int failedPermanently;

  /// Number of operations remaining in the queue.
  final int pending;

  /// Whether this pass did no work because connectivity was offline.
  final bool skippedOffline;

  /// Whether no queued work remains.
  bool get isQueueEmpty => pending == 0;
}
