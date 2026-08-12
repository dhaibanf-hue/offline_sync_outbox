import 'dart:math' as math;

/// Configurable exponential-backoff policy for failed operations.
final class SyncRetryPolicy {
  /// Creates a retry policy.
  SyncRetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.multiplier = 2,
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
          maxAttempts, 'maxAttempts', 'Must be at least 1.');
    }
    if (initialDelay.isNegative || maxDelay.isNegative) {
      throw ArgumentError('Retry delays must not be negative.');
    }
    if (maxDelay < initialDelay) {
      throw ArgumentError('maxDelay must be greater than initialDelay.');
    }
    if (multiplier < 1) {
      throw ArgumentError.value(
          multiplier, 'multiplier', 'Must be at least 1.');
    }
  }

  /// Maximum total processing attempts before permanent failure.
  final int maxAttempts;

  /// Delay after the first failed attempt.
  final Duration initialDelay;

  /// Upper bound applied to calculated retry delays.
  final Duration maxDelay;

  /// Exponential growth factor.
  final double multiplier;

  /// Returns whether another attempt is allowed after [failedAttemptCount].
  bool canRetryAfter(int failedAttemptCount) {
    return failedAttemptCount < maxAttempts;
  }

  /// Calculates the delay after a one-based failed attempt count.
  Duration delayAfter(int failedAttemptCount) {
    if (failedAttemptCount < 1) {
      throw ArgumentError.value(
        failedAttemptCount,
        'failedAttemptCount',
        'Must be at least 1.',
      );
    }
    final factor = math.pow(multiplier, failedAttemptCount - 1);
    final calculated = (initialDelay.inMicroseconds * factor).round();
    return Duration(
      microseconds: math.min(calculated, maxDelay.inMicroseconds),
    );
  }
}
