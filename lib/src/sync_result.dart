/// The action the manager should take after processing an operation.
enum SyncDisposition {
  /// Remove the operation because it completed successfully.
  success,

  /// Keep the operation and retry it later.
  retry,

  /// Remove the operation without retrying it.
  discard,
}

/// Describes the outcome returned by a sync processor.
final class SyncResult {
  /// Marks an operation as successfully synchronized.
  const SyncResult.success({this.reason})
      : disposition = SyncDisposition.success,
        retryAfter = null;

  /// Schedules an operation for another attempt.
  const SyncResult.retry({this.reason, this.retryAfter})
      : disposition = SyncDisposition.retry;

  /// Removes an operation intentionally, for example after a validation error.
  const SyncResult.discard({this.reason})
      : disposition = SyncDisposition.discard,
        retryAfter = null;

  /// The action the manager should take.
  final SyncDisposition disposition;

  /// Optional diagnostic text included in emitted events.
  final String? reason;

  /// Optional server-directed delay that overrides the configured retry policy.
  final Duration? retryAfter;
}
