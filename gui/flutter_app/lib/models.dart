class BootstrapInfo {
  final String version;
  final bool disclaimerAccepted;
  final bool cookieConfigured;
  final bool cookieLoggedIn;

  const BootstrapInfo({
    required this.version,
    required this.disclaimerAccepted,
    required this.cookieConfigured,
    required this.cookieLoggedIn,
  });

  factory BootstrapInfo.fromJson(Map<String, dynamic> json) => BootstrapInfo(
        version: json['version'] as String? ?? '',
        disclaimerAccepted: json['disclaimer_accepted'] as bool? ?? false,
        cookieConfigured: json['cookie_configured'] as bool? ?? false,
        cookieLoggedIn: json['cookie_logged_in'] as bool? ?? false,
      );
}

class CookieStatus {
  final bool configured;
  final bool loggedIn;

  const CookieStatus({required this.configured, required this.loggedIn});

  factory CookieStatus.fromJson(Map<String, dynamic> json) => CookieStatus(
        configured: json['configured'] as bool? ?? false,
        loggedIn: json['logged_in'] as bool? ?? false,
      );
}

class CookieResult {
  final bool success;
  final bool loggedIn;
  final String message;

  const CookieResult({
    required this.success,
    required this.loggedIn,
    required this.message,
  });

  factory CookieResult.fromJson(Map<String, dynamic> json) => CookieResult(
        success: json['success'] as bool? ?? false,
        loggedIn: json['logged_in'] as bool? ?? false,
        message: json['message'] as String? ?? '',
      );
}

class TaskInfo {
  final String id;
  final String type;
  final String label;
  final String status;
  final String message;
  final String createdAt;
  final String finishedAt;
  final List<String> logs;
  final String downloadDir;
  final Map<String, dynamic> progress;

  const TaskInfo({
    required this.id,
    required this.type,
    required this.label,
    required this.status,
    required this.message,
    required this.createdAt,
    required this.finishedAt,
    required this.logs,
    required this.downloadDir,
    required this.progress,
  });

  bool get isRunning => status == 'running';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        status: json['status'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        finishedAt: json['finished_at'] as String? ?? '',
        logs: (json['logs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        downloadDir: json['download_dir'] as String? ?? '',
        progress: json['progress'] is Map
            ? Map<String, dynamic>.from(json['progress'] as Map)
            : const {},
      );
}

class WorkPreview {
  final String title;
  final String author;
  final String coverUrl;
  final bool isGallery;
  final Map<String, dynamic> rawData;

  const WorkPreview({
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.isGallery,
    required this.rawData,
  });

  static WorkPreview? tryParse(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    String cover = '';
    if (data['video'] is Map) {
      final video = data['video'] as Map<String, dynamic>;
      if (video['cover'] is Map) {
        final c = video['cover'] as Map<String, dynamic>;
        if (c['url_list'] is List && (c['url_list'] as List).isNotEmpty) {
          cover = (c['url_list'] as List).first.toString();
        }
      }
    }
    if (cover.isEmpty && data['images'] is List) {
      final images = data['images'] as List;
      if (images.isNotEmpty && images.first is Map) {
        final first = images.first as Map<String, dynamic>;
        if (first['url_list'] is List &&
            (first['url_list'] as List).isNotEmpty) {
          cover = (first['url_list'] as List).first.toString();
        }
      }
    }
    return WorkPreview(
      title: data['desc']?.toString() ?? '无标题',
      author: data['author'] is Map
          ? ((data['author'] as Map)['nickname']?.toString() ?? '')
          : '',
      coverUrl: cover,
      isGallery: data['images'] != null,
      rawData: data,
    );
  }
}
