import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api_service.dart';

// Top-level background dispatcher for Android & iOS
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await SyncEngine.runBackgroundSync();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

class SyncEngine {
  static const String taskName = 'dgcloud_background_auto_sync';

  // Initialize periodic background worker
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Register 15-minute periodic auto-sync task
    await Workmanager().registerPeriodicTask(
      'dgcloud_periodic_sync_id',
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected, // Uploads as soon as internet is available
      ),
    );
  }

  // Get user-selected auto-sync folders (Camera, Downloads, Documents, or Custom paths)
  static Future<List<String>> getSyncFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('sync_folders') ?? [];
  }

  static Future<void> addSyncFolder(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final folders = await getSyncFolders();
    if (!folders.contains(folderPath)) {
      folders.add(folderPath);
      await prefs.setStringList('sync_folders', folders);
    }
  }

  static Future<void> removeSyncFolder(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final folders = await getSyncFolders();
    folders.remove(folderPath);
    await prefs.setStringList('sync_folders', folders);
  }

  // Core Background Sync Loop: Inspects folders and uploads newly added files
  static Future<void> runBackgroundSync() async {
    final token = await ApiService.getToken();
    if (token == null) return; // Not logged in

    final folders = await getSyncFolders();
    final prefs = await SharedPreferences.getInstance();
    final syncedFiles = prefs.getStringList('already_synced_files') ?? [];

    for (final folderPath in folders) {
      final dir = Directory(folderPath);
      if (!await dir.exists()) continue;

      final entities = dir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is File) {
          final filePath = entity.path;
          final fileName = entity.uri.pathSegments.last;

          // Skip if already synced
          if (syncedFiles.contains(filePath)) continue;

          try {
            await ApiService.uploadFile(
              file: entity,
              fileName: fileName,
              isCloudPinned: false,
            );

            // Record as successfully synced
            syncedFiles.add(filePath);
            await prefs.setStringList('already_synced_files', syncedFiles);
          } catch (e) {
            // Will retry on next background cycle
          }
        }
      }
    }
  }
}

