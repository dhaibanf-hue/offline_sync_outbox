import 'package:offline_sync_manager/offline_sync_manager.dart';
import 'package:test/test.dart';

void main() {
  test('operation round-trips through JSON', () {
    final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final nextAttemptAt = createdAt.add(const Duration(seconds: 10));
    final operation = SyncOperation(
      id: 'operation-1',
      action: 'create_order',
      payload: <String, Object?>{
        'orderId': 42,
        'items': <String>['coffee', 'tea'],
      },
      createdAt: createdAt,
      attemptCount: 2,
      nextAttemptAt: nextAttemptAt,
    );

    final restored = SyncOperation.fromJson(operation.toJson());

    expect(restored.id, operation.id);
    expect(restored.action, operation.action);
    expect(restored.payload, operation.payload);
    expect(restored.createdAt, createdAt);
    expect(restored.attemptCount, 2);
    expect(restored.nextAttemptAt, nextAttemptAt);
  });

  test('pending operations receive unique IDs', () {
    final timestamp = DateTime.utc(2026);

    final first = SyncOperation.pending(action: 'first', createdAt: timestamp);
    final second =
        SyncOperation.pending(action: 'second', createdAt: timestamp);

    expect(first.id, isNot(second.id));
  });
}
