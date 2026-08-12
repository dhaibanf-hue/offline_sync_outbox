import 'dart:io';

import 'package:offline_sync_outbox/offline_sync_outbox.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('offline_sync_demo_');
  final path = '${directory.path}${Platform.pathSeparator}offline-queue.json';
  final connectivity = ManualSyncConnectivity(isOnline: false);

  final manager = OfflineSyncManager(
    store: JsonFileSyncStore(path),
    connectivity: connectivity,
    autoSync: false,
    processor: (operation) async {
      stdout.writeln(
        'Uploading ${operation.action}: ${operation.payload}',
      );
      return const SyncResult.success();
    },
  );

  await manager.initialize();
  try {
    await manager.enqueue(
      action: 'create_note',
      payload: <String, Object?>{'text': 'Written while offline'},
    );

    final offline = await manager.synchronize();
    stdout.writeln('Pending while offline: ${offline.pending}');

    connectivity.setOnline(true);
    final synced = await manager.synchronize();
    stdout.writeln('Uploaded: ${synced.succeeded}');
  } finally {
    await manager.dispose();
    await directory.delete(recursive: true);
  }
}
