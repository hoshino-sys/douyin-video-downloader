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

class PlatformCookieState {
  final bool imported;
  final bool loggedIn;

  const PlatformCookieState({required this.imported, required this.loggedIn});

  factory PlatformCookieState.fromJson(Map<String, dynamic> json) =>
      PlatformCookieState(
        imported: json['imported'] as bool? ?? false,
        loggedIn: json['logged_in'] as bool? ?? false,
      );
}

class CookieStatus {
  final bool configured;
  final bool loggedIn;
  final Map<String, PlatformCookieState> platforms;

  const CookieStatus({
    required this.configured,
    required this.loggedIn,
    this.platforms = const {},
  });

  /// 四个平台是否全部已导入 Cookie（旧后端无 platforms 时退回 configured）
  bool get allImported => platforms.isEmpty
      ? configured
      : platforms.values.every((p) => p.imported);

  /// 未导入 Cookie 的平台 key 列表
  List<String> get missingPlatforms => platforms.entries
      .where((e) => !e.value.imported)
      .map((e) => e.key)
      .toList();

  factory CookieStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['platforms'];
    final map = <String, PlatformCookieState>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          map[key.toString()] =
              PlatformCookieState.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }
    return CookieStatus(
      configured: json['configured'] as bool? ?? false,
      loggedIn: json['logged_in'] as bool? ?? false,
      platforms: map,
    );
  }
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

class PlatformCookieResult {
  final bool success;
  final bool loggedIn;
  final String message;

  const PlatformCookieResult({
    required this.success,
    required this.loggedIn,
    required this.message,
  });

  static PlatformCookieResult fromJson(Map<String, dynamic> json) =>
      PlatformCookieResult(
        success: json['success'] as bool? ?? false,
        loggedIn: json['logged_in'] as bool? ?? false,
        message: json['message']?.toString() ?? '',
      );
}

class CookieAllResult {
  final bool success;
  final Map<String, PlatformCookieResult> results;

  const CookieAllResult({
    required this.success,
    required this.results,
  });

  static const Map<String, String> labels = {
    'douyin': '抖音',
    'tiktok': 'TikTok',
    'bili': 'B站',
    'youtube': 'YouTube',
  };

  String summary() {
    final parts = <String>[];
    for (final entry in labels.entries) {
      final r = results[entry.key];
      if (r == null) continue;
      final mark = r.success ? (r.loggedIn ? '✓' : '✓未登录') : '✗';
      parts.add('${entry.value}$mark');
    }
    return parts.join('  ');
  }

  static CookieAllResult fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    final map = <String, PlatformCookieResult>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          map[entry.key.toString()] = PlatformCookieResult.fromJson(
              Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }
    return CookieAllResult(
      success: json['success'] as bool? ?? false,
      results: map,
    );
  }
}

class TaskInfo {
  final String id;
  final String type;
  final String label;
  final String title;
  final String platform;
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
    this.title = '',
    this.platform = '',
    required this.status,
    required this.message,
    required this.createdAt,
    required this.finishedAt,
    required this.logs,
    required this.downloadDir,
    required this.progress,
  });

  bool get isRunning => status == 'running';
  bool get isPaused => status == 'paused';
  bool get isCancelled => status == 'cancelled';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  /// 暂停中：进度条保留但不再刷新
  bool get isActive => isRunning || isPaused;

  /// 卡片大标题：视频标题 → 当前状态文本 → 任务名 兜底
  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (message.isNotEmpty) return message;
    return label;
  }

  // 下载进度明细（ytdlp/update 任务由后端实时更新）
  int get currentBytes => (progress['current'] as num?)?.toInt() ?? 0;
  int get totalBytes => (progress['total'] as num?)?.toInt() ?? 0;
  double get speedBytes => (progress['speed'] as num?)?.toDouble() ?? 0;
  int get etaSeconds => (progress['eta'] as num?)?.toInt() ?? 0;

  /// 0.0~1.0 的确定进度；总量未知时返回 null（不定态）
  double? get progressValue => totalBytes > 0
      ? (currentBytes / totalBytes).clamp(0.0, 1.0)
      : null;

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        label: json['label'] as String? ?? '',
        title: json['title']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
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

class UpdateCheckInfo {
  final String current;
  final String latest;
  final bool updateAvailable;
  final String notes;
  final String pageUrl;
  final String zipUrl;
  final String updateMode; // patch=增量补丁包 | full=全量包
  final int zipSize; // 更新包字节数（API 限额回退时为 0，未知）
  final String error;

  const UpdateCheckInfo({
    required this.current,
    required this.latest,
    required this.updateAvailable,
    required this.notes,
    required this.pageUrl,
    required this.zipUrl,
    this.updateMode = 'full',
    this.zipSize = 0,
    required this.error,
  });

  bool get hasError => error.isNotEmpty;
  bool get isPatch => updateMode == 'patch';

  String get sizeLabel {
    if (zipSize <= 0) return '';
    final mb = zipSize / 1024 / 1024;
    return mb >= 1 ? '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB' : '${(zipSize / 1024).toStringAsFixed(0)} KB';
  }

  factory UpdateCheckInfo.fromJson(Map<String, dynamic> json) =>
      UpdateCheckInfo(
        current: json['current']?.toString() ?? '',
        latest: json['latest']?.toString() ?? '',
        updateAvailable: json['update_available'] as bool? ?? false,
        notes: json['notes']?.toString() ?? '',
        pageUrl: json['page_url']?.toString() ?? '',
        zipUrl: json['zip_url']?.toString() ?? '',
        updateMode: json['update_mode']?.toString() ?? 'full',
        zipSize: (json['zip_size'] as num?)?.toInt() ?? 0,
        error: json['error']?.toString() ?? '',
      );
}

class YtdlpFormat {
  final String formatId;
  final String label;
  final String ext;
  final int? height;
  final int? filesize;

  const YtdlpFormat({
    required this.formatId,
    required this.label,
    required this.ext,
    this.height,
    this.filesize,
  });

  static YtdlpFormat fromJson(Map<String, dynamic> json) => YtdlpFormat(
        formatId: json['format_id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        ext: json['ext']?.toString() ?? '',
        height: (json['height'] as num?)?.toInt(),
        filesize: (json['filesize'] as num?)?.toInt(),
      );
}

class YtdlpPreview {
  final String platform; // bili | youtube | douyin
  final String kind; // video | batch
  final bool isBatch;
  final String title;
  final String uploader;
  final String thumbnail;
  final int? duration;
  final List<YtdlpFormat> formats;
  final int? itemCount;
  final List<String> sampleTitles;
  final String error;

  const YtdlpPreview({
    required this.platform,
    required this.kind,
    required this.isBatch,
    required this.title,
    required this.uploader,
    required this.thumbnail,
    this.duration,
    required this.formats,
    this.itemCount,
    required this.sampleTitles,
    required this.error,
  });

  bool get hasError => error.isNotEmpty;

  String get platformName =>
      platform == 'bili' ? 'B站' : platform == 'youtube' ? 'YouTube' : '抖音';

  static YtdlpPreview fromJson(Map<String, dynamic> json) {
    final kind = json['kind']?.toString() ?? 'video';
    return YtdlpPreview(
      platform: json['platform']?.toString() ?? 'douyin',
      kind: kind,
      isBatch: kind == 'batch',
      title: json['title']?.toString() ?? '',
      uploader: json['uploader']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      duration: (json['duration'] as num?)?.toInt(),
      formats: (json['formats'] as List?)
              ?.map((e) =>
                  YtdlpFormat.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      itemCount: (json['item_count'] as num?)?.toInt(),
      sampleTitles: (json['sample_titles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      error: json['error']?.toString() ?? '',
    );
  }
}

class WorkPreview {
  final String title;
  final String author;
  final String coverUrl;
  final bool isGallery;
  final List<String> imageUrls;
  final Map<String, dynamic> rawData;

  const WorkPreview({
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.isGallery,
    required this.imageUrls,
    required this.rawData,
  });

  static WorkPreview? tryParse(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    final downloads = data['downloads'];
    final downloadUrls = downloads is List
        ? downloads.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final type = data['type']?.toString() ?? '';

    String cover = '';
    if (data['static_cover'] is String && (data['static_cover'] as String).isNotEmpty) {
      cover = data['static_cover'] as String;
    }
    if (cover.isEmpty && data['dynamic_cover'] is String) {
      cover = data['dynamic_cover'] as String;
    }
    String author = data['nickname']?.toString() ?? '';

    var isGallery = type.contains('图集');
    var imageUrls = downloadUrls;

    if (cover.isEmpty && data['video'] is Map) {
      final video = data['video'] as Map<String, dynamic>;
      if (video['cover'] is Map) {
        final c = video['cover'] as Map<String, dynamic>;
        if (c['url_list'] is List && (c['url_list'] as List).isNotEmpty) {
          cover = (c['url_list'] as List).first.toString();
        }
      }
    }
    if (data['images'] is List) {
      final images = data['images'] as List;
      final urls = <String>[];
      for (final img in images) {
        if (img is Map && img['url_list'] is List && (img['url_list'] as List).isNotEmpty) {
          urls.add((img['url_list'] as List).first.toString());
        }
      }
      if (urls.isNotEmpty) {
        isGallery = true;
        imageUrls = urls;
      }
    }
    if (author.isEmpty && data['author'] is Map) {
      author = (data['author'] as Map)['nickname']?.toString() ?? '';
    }
    if (type.isEmpty && downloadUrls.length > 1) {
      isGallery = true;
    }
    return WorkPreview(
      title: data['desc']?.toString() ?? '无标题',
      author: author,
      coverUrl: cover,
      isGallery: isGallery,
      imageUrls: imageUrls,
      rawData: data,
    );
  }
}
