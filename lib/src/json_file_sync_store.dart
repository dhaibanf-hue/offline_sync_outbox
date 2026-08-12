import 'dart:convert';
import 'dart:io';

import 'sync_operation.dart';
import 'sync_store.dart';

/// A durable JSON file store for mobile, desktop, and server Dart runtimes.
///
/// Writes use a temporary file and a backup before replacement. Applications
/// should create only one manager for a given [path].
final class JsonFileSyncStore implements SyncStore {
  /// Creates a JSON-backed store at [path].
  JsonFileSyncStore(this.path);

  /// Location of the queue file.
  final String path;

  bool _initialized = false;
  bool _closed = false;

  File get _file => File(path);

  @override
  Future<void> initialize() async {
    if (_closed) {
      throw StateError('The store has already been closed.');
    }
    try {
      await _file.parent.create(recursive: true);
      if (!await _file.exists()) {
        await _file.writeAsString('[]\n', flush: true);
      }
      _initialized = true;
    } on Object catch (error) {
      throw SyncStoreException(
        'Could not initialize the queue file at $path.',
        cause: error,
      );
    }
  }

  @override
  Future<List<SyncOperation>> readAll() async {
    _ensureReady();
    try {
      final contents = await _file.readAsString();
      final decoded = jsonDecode(contents);
      if (decoded is! List) {
        throw const FormatException('The queue root must be a JSON list.');
      }
      return List<SyncOperation>.unmodifiable(
        decoded.map((Object? item) {
          if (item is! Map) {
            throw const FormatException('Each queue item must be an object.');
          }
          return SyncOperation.fromJson(Map<String, Object?>.from(item));
        }),
      );
    } on Object catch (error) {
      throw SyncStoreException(
        'Could not read the queue file at $path.',
        cause: error,
      );
    }
  }

  @override
  Future<void> writeAll(List<SyncOperation> operations) async {
    _ensureReady();
    final temporary = File('$path.$pid.tmp');
    final backup = File('$path.$pid.bak');
    var movedOriginal = false;

    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (await backup.exists()) {
        await backup.delete();
      }

      final json = jsonEncode(
        operations.map((operation) => operation.toJson()).toList(),
      );
      await temporary.writeAsString('$json\n', flush: true);

      if (await _file.exists()) {
        await _file.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(_file.path);
      if (movedOriginal && await backup.exists()) {
        await backup.delete();
      }
    } on Object catch (error) {
      if (!await _file.exists() && await backup.exists()) {
        await backup.rename(_file.path);
      }
      if (await temporary.exists()) {
        await temporary.delete();
      }
      throw SyncStoreException(
        'Could not persist the queue file at $path.',
        cause: error,
      );
    }
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
