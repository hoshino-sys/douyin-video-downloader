import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  final String baseUrl;
  final http.Client _client = http.Client();

  ApiClient({required this.baseUrl});

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'))
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiException('请求失败 (HTTP ${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('响应格式错误');
    }
    return decoded;
  }

  /// 经后端代理加载图片（前端直连不了的图床，如 YouTube 封面 i.ytimg.com）
  String thumbnailUrl(String rawUrl) =>
      '$baseUrl/api/gui/thumbnail?url=${Uri.encodeComponent(rawUrl)}';

  // ---- GUI ----

  Future<BootstrapInfo> bootstrap() async =>
      BootstrapInfo.fromJson(await get('/api/gui/bootstrap'));

  Future<CookieStatus> cookieStatus() async =>
      CookieStatus.fromJson(await get('/api/gui/cookie/status'));

  Future<void> acceptDisclaimer() =>
      post('/api/gui/disclaimer/accept');

  Future<List<String>> cookieBrowsers() async {
    final data = await get('/api/gui/cookie/browsers');
    return List<String>.from(data['browsers'] as List? ?? []);
  }

  Future<CookieResult> cookieFromBrowser(String browser,
      {String target = 'douyin'}) async =>
      CookieResult.fromJson(await post(
        '/api/gui/cookie/browser',
        body: {'browser': browser, 'target': target},
        timeout: const Duration(seconds: 120),
      ));

  Future<CookieAllResult> cookieFromBrowserAll(String browser) async =>
      CookieAllResult.fromJson(await post(
        '/api/gui/cookie/browser',
        body: {'browser': browser, 'target': 'all'},
        timeout: const Duration(seconds: 180),
      ));

  Future<CookieResult> cookiePaste(String text) async =>
      CookieResult.fromJson(await post(
        '/api/gui/cookie/paste',
        body: {'text': text},
      ));

  Future<Map<String, dynamic>> settings() => get('/settings');

  Future<void> saveSettings(Map<String, dynamic> data) =>
      post('/api/gui/settings', body: data);

  // ---- 数据查询 ----

  Future<String?> expandShareText(
      String text, bool tiktok) async {
    final path = tiktok ? '/tiktok/share' : '/douyin/share';
    try {
      final data = await post(path, body: {'text': text});
      return data['url'] as String?;
    } on ApiException catch (e) {
      if (e.message.contains('404')) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> workDetail(
      String detailId, bool tiktok) async {
    final path = tiktok ? '/tiktok/detail' : '/douyin/detail';
    final data = await post(path, body: {'detail_id': detailId},
        timeout: const Duration(seconds: 90));
    final payload = data['data'];
    return payload is Map<String, dynamic> ? payload : null;
  }

  // ---- B站/YouTube (yt-dlp) ----

  Future<YtdlpPreview> detectUrl(String url) async =>
      YtdlpPreview.fromJson(await post(
        '/api/gui/detect',
        body: {'url': url},
        timeout: const Duration(seconds: 120),
      ));

  Future<TaskInfo?> createYtdlpTask({
    required String url,
    String? formatId,
    String? label,
    String? platform,
    String? saveDir,
  }) async {
    final result = await post('/api/gui/task', body: {
      'type': 'ytdlp',
      'url': url,
      'platform': ?platform,
      'format_id': ?formatId,
      'label': ?label,
      'save_dir': ?saveDir,
    }, timeout: const Duration(seconds: 60));
    if (result['status'] != 'success') {
      throw ApiException(result['message']?.toString() ?? '创建任务失败');
    }
    return TaskInfo.fromJson(
        result['task'] as Map<String, dynamic>? ?? {});
  }

  // ---- 任务 ----

  Future<TaskInfo?> createDetailTask({
    required bool tiktok,
    required Map<String, dynamic> data,
    String? saveDir,
  }) async {
    final result = await post('/api/gui/task', body: {
      'type': 'detail',
      'platform': tiktok ? 'tiktok' : 'douyin',
      'data': data,
      'save_dir': ?saveDir,
    });
    if (result['status'] != 'success') {
      throw ApiException(result['message']?.toString() ?? '创建任务失败');
    }
    return TaskInfo.fromJson(
        result['task'] as Map<String, dynamic>? ?? {});
  }

  Future<TaskInfo?> createAccountTask({
    required bool tiktok,
    required String secUserId,
    required String tab,
    required String earliest,
    required String latest,
    String? saveDir,
  }) async {
    final result = await post('/api/gui/task', body: {
      'type': 'account',
      'platform': tiktok ? 'tiktok' : 'douyin',
      'sec_user_id': secUserId,
      'tab': tab,
      'earliest': earliest,
      'latest': latest,
      'save_dir': ?saveDir,
    });
    if (result['status'] != 'success') {
      throw ApiException(result['message']?.toString() ?? '创建任务失败');
    }
    return TaskInfo.fromJson(
        result['task'] as Map<String, dynamic>? ?? {});
  }

  Future<List<TaskInfo>> tasks() async {
    final data = await get('/api/gui/tasks');
    return ((data['tasks'] as List?) ?? [])
        .map((e) => TaskInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<bool> openFolder(String path) async {
    try {
      final r = await post('/api/gui/open_folder', body: {'path': path});
      return r['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---- 应用更新 ----

  Future<UpdateCheckInfo> updateCheck() async =>
      UpdateCheckInfo.fromJson(await get('/api/gui/update/check'));

  /// 在应用内下载更新包（进度在任务页可见，完成后自动打开所在文件夹）
  Future<TaskInfo?> updateDownload(String url) async {
    final result = await post(
      '/api/gui/update/download',
      body: {'url': url},
      timeout: const Duration(seconds: 60),
    );
    if (result['status'] != 'success') {
      throw ApiException(result['message']?.toString() ?? '创建下载任务失败');
    }
    return TaskInfo.fromJson(
        result['task'] as Map<String, dynamic>? ?? {});
  }

  void dispose() => _client.close();
}
