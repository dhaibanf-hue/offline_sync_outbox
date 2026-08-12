import 'sync_operation.dart';
import 'sync_store.dart';

/// An in-memory [SyncStore] useful for tests and ephemeral queues.
final class MemorySyncStore implements SyncStore {
  List<SyncOperation> _operations = <SyncOperation>[];
  bool _initialized = false;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    if (_closed) {
      throw StateError('The store has already been closed.');
    }
    _initialized = true;
  }

  @override
  Future<List<SyncOperation>> readAll() async {
    _ensureReady();
    return List<SyncOperation>.unmodifiable(_operations);
  }

  @override
  Future<void> writeAll(List<SyncOperation> operations) async {
    _ensureReady();
    _operations = List<SyncOperation>.of(operations);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  void _ensureReady() {
    if (!_initialized) {
      throw StateError('Call initialize() before using the store.');
    }
    if (_closed) {
      throw StateError('The store has already been closed.');
    }
  }
}
