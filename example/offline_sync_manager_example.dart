import 'dart:io';

import 'package:offline_sync_manager/offline_sync_manager.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('offline_sync_demo_');
  final queuePath =
      '${directory.path}${Platform.pathSeparator}offline-queue.json';
  final connectivity = ManualSyncConnectivity(isOnline: false);

  final manager = OfflineSyncManager(
    store: JsonFileSyncStore(queuePath),
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
  await manager.enqueue(
    action: 'create_note',
    payload: <String, Object?>{'text': 'Written while offline'},
  );

  final offlineReport = await manager.synchronize();
  stdout.writeln('Pending while offline: ${offlineReport.pending}');

  connectivity.setOnline(true);
  final onlineReport = await manager.synchronize();
  stdout.writeln('Uploaded: ${onlineReport.succeeded}');

  await manager.dispose();
  await directory.delete(recursive: true);
}
