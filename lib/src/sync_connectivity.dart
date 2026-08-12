import 'dart:async';

/// Connectivity source used to pause and resume synchronization.
abstract interface class SyncConnectivity {
  /// Emits online-state changes.
  Stream<bool> get changes;

  /// Returns whether processing is currently allowed.
  Future<bool> isOnline();

  /// Releases connectivity resources.
  Future<void> dispose();
}

/// Connectivity source that is always online.
final class AlwaysOnlineSyncConnectivity implements SyncConnectivity {
  /// Creates an always-online connectivity source.
  const AlwaysOnlineSyncConnectivity();

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<bool> isOnline() async => true;

  @override
  Future<void> dispose() async {}
}

/// Manually controlled connectivity source for tests and custom adapters.
final class ManualSyncConnectivity implements SyncConnectivity {
  /// Creates a source with an initial online state.
  ManualSyncConnectivity({bool isOnline = true}) : _isOnline = isOnline;

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast(sync: true);
  bool _isOnline;
  bool _disposed = false;

  @override
  Stream<bool> get changes => _controller.stream;

  @override
  Future<bool> isOnline() async => _isOnline;

  /// Changes the current state and notifies listeners when it differs.
  void setOnline(bool value) {
    if (_disposed) {
      throw StateError('The connectivity source has been disposed.');
    }
    if (_isOnline == value) {
      return;
    }
    _isOnline = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _controller.close();
  }
}
