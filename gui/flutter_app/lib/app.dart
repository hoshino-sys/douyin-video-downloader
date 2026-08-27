import 'package:file_selector/file_selector.dart';

import 'services/api_client.dart';
import 'services/backend_process.dart';

class App {
  static BackendProcess? backend;
  static ApiClient? client;

  static Future<String?> showFolderPicker() async {
    try {
      final dir = await getDirectoryPath();
      return (dir == null || dir.isEmpty) ? null : dir;
    } catch (_) {
      return null;
    }
  }

  static void reset() {
    backend?.kill();
    client?.dispose();
    backend = null;
    client = null;
  }
}
