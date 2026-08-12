import 'dart:io';

import 'package:offline_sync_outbox/offline_sync_outbox.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'offline_sync_outbox_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists queue order between store instances', () async {
    final path =
        '${temporaryDirectory.path}${Platform.pathSeparator}queue.json';
    final firstStore = JsonFileSyncStore(path);
    await firstStore.initialize();
    await firstStore.writeAll(<SyncOperation>[
      SyncOperation.pending(id: 'one', action: 'first'),
      SyncOperation.pending(id: 'two', action: 'second'),
    ]);
    await firstStore.close();

    final secondStore = JsonFileSyncStore(path);
    await secondStore.initialize();
    final restored = await secondStore.readAll();

    expect(restored.map((item) => item.id), <String>['one', 'two']);
    await secondStore.close();
  });

  test('reports malformed queue data', () async {
    final path =
        '${temporaryDirectory.path}${Platform.pathSeparator}queue.json';
    final file = File(path);
    await file.writeAsString('{not-json');
    final store = JsonFileSyncStore(path);
    await store.initialize();

    expect(store.readAll, throwsA(isA<SyncStoreException>()));
    await store.close();
  });
}
