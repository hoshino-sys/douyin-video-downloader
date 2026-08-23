import 'services/api_client.dart';
import 'services/backend_process.dart';

class App {
  static BackendProcess? backend;
  static ApiClient? client;

  static void reset() {
    backend?.kill();
    client?.dispose();
    backend = null;
    client = null;
  }
}
