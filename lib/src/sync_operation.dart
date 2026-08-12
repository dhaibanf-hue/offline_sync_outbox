/// A serializable unit of work stored in the offline queue.
final class SyncOperation {
  /// Creates an operation with an explicit identity and timestamp.
  SyncOperation({
    required this.id,
    required this.action,
    required Map<String, Object?> payload,
    required this.createdAt,
    this.attemptCount = 0,
    this.nextAttemptAt,
  }) : payload = Map<String, Object?>.unmodifiable(payload) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (action.trim().isEmpty) {
      throw ArgumentError.value(action, 'action', 'Must not be empty.');
    }
    if (attemptCount < 0) {
      throw ArgumentError.value(
        attemptCount,
        'attemptCount',
        'Must not be negative.',
      );
    }
  }

  static int _sequence = 0;
  static const Object _notProvided = Object();

  /// Creates a new pending operation and generates a process-unique ID.
  factory SyncOperation.pending({
    String? id,
    required String action,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? createdAt,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final generatedId =
        'sync-${timestamp.microsecondsSinceEpoch}-${_sequence++}';
    return SyncOperation(
      id: id ?? generatedId,
      action: action,
      payload: payload,
      createdAt: timestamp,
    );
  }

  /// Restores an operation from its JSON representation.
  factory SyncOperation.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final action = json['action'];
    final payload = json['payload'];
    final createdAt = json['createdAt'];
    final attemptCount = json['attemptCount'];
    final nextAttemptAt = json['nextAttemptAt'];

    if (id is! String || action is! String || createdAt is! String) {
      throw const FormatException(
          'Operation identity or timestamp is invalid.');
    }
    if (payload is! Map) {
      throw const FormatException('Operation payload must be a JSON object.');
    }
    if (attemptCount is! int) {
      throw const FormatException('Operation attemptCount must be an integer.');
    }
    if (nextAttemptAt != null && nextAttemptAt is! String) {
      throw const FormatException('Operation nextAttemptAt must be a string.');
    }

    return SyncOperation(
      id: id,
      action: action,
      payload: Map<String, Object?>.from(payload),
      createdAt: DateTime.parse(createdAt).toUtc(),
      attemptCount: attemptCount,
      nextAttemptAt: nextAttemptAt == null
          ? null
          : DateTime.parse(nextAttemptAt as String).toUtc(),
    );
  }

  /// Stable identifier used for deduplication and removal.
  final String id;

  /// Application-defined action name, such as `create_order`.
  final String action;

  /// JSON-encodable data needed by the processor.
  final Map<String, Object?> payload;

  /// UTC time at which the operation entered the queue.
  final DateTime createdAt;

  /// Number of failed processing attempts already made.
  final int attemptCount;

  /// Earliest UTC time at which this operation may be retried.
  final DateTime? nextAttemptAt;

  /// Returns a copy with selected fields replaced.
  SyncOperation copyWith({
    int? attemptCount,
    Object? nextAttemptAt = _notProvided,
  }) {
    return SyncOperation(
      id: id,
      action: action,
      payload: payload,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: identical(nextAttemptAt, _notProvided)
          ? this.nextAttemptAt
          : nextAttemptAt as DateTime?,
    );
  }

  /// Converts this operation to a JSON-encodable map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'action': action,
      'payload': payload,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'attemptCount': attemptCount,
      'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'SyncOperation(id: $id, action: $action, attempts: $attemptCount)';
  }
}
