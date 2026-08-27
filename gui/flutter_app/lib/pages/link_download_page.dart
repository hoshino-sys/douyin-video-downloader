import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models.dart';
import '../services/toast.dart';
import '../widgets/save_to_chip.dart';

class LinkDownloadPage extends StatefulWidget {
  final VoidCallback? onGoTasks;

  const LinkDownloadPage({super.key, this.onGoTasks});

  @override
  State<LinkDownloadPage> createState() => _LinkDownloadPageState();
}

class _LinkDownloadPageState extends State<LinkDownloadPage>
    with WidgetsBindingObserver {
  bool _batchMode = false;
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  bool _parsing = false;
  bool _downloading = false;
  WorkPreview? _preview;
  YtdlpPreview? _ytPreview;
  String? _selectedHeight;
  bool _lastTiktok = false;
  String? _saveDir;
  String? _error;
  List<_BatchItem> _batchItems = [];
  String? _lastClipboard;
  Timer? _clipTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedLastClipboard();
    _clipTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollClipboard());
  }

  Future<void> _seedLastClipboard() async {
    final text = await _readClipboardWithRetry(attempts: 2);
    if (text != null && text.trim().isNotEmpty) {
      _lastClipboard = text.trim();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onWindowFocusRegained();
    }
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toast(String message, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    AppToast.show(context, message, actionLabel: actionLabel, onAction: onAction);
  }

  Future<void> _pollClipboard() async {
    if (!mounted || _parsing || _downloading) return;
    String? text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _lastClipboard) return;
    _lastClipboard = trimmed;
    if (!_looksLikeShareText(trimmed)) return;
    if (_inputController.text.trim().contains(trimmed)) return;
    _importText(trimmed);
  }

  Future<String?> _readClipboardWithRetry({int attempts = 5}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final t = data?.text;
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  bool _looksLikeShareText(String t) {
    final lower = t.toLowerCase();
    return t.contains('http') ||
        t.contains('抖音') ||
        lower.contains('douyin') ||
        lower.contains('tiktok') ||
        RegExp(r'\d{15,}').hasMatch(t);
  }

  Future<void> _onWindowFocusRegained() async {
    final text = await _readClipboardWithRetry(attempts: 3);
    if (!mounted) return;
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _lastClipboard) return;
    _lastClipboard = trimmed;
    if (!_looksLikeShareText(trimmed)) return;
    _importText(trimmed);
  }

  void _importText(String text) {
    setState(() {
      final current = _inputController.text.trim();
      if (current.isEmpty) {
        _inputController.text = text;
      } else if (current.contains(text)) {
        return;
      } else {
        _inputController.text = '$current\n$text';
      }
      _inputController.selection =
          TextSelection.collapsed(offset: _inputController.text.length);
    });
    _focusNode.requestFocus();
    _toast('检测到剪贴板新内容，已导入');
  }

  String? _extractIdFromUrl(String url) {
    for (final pattern in [
      RegExp(r'video/(\d+)'),
      RegExp(r'modal_id=(\d+)'),
      RegExp(r'note/(\d+)'),
      RegExp(r'photo/(\d+)'),
      RegExp(r'/(\d{15,})'),
    ]) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// 返回识别的平台：bili / youtube / douyin / tiktok；无法识别返回 null。
  String? _quickDetect(String url) {
    final u = url.trim();
    bool has(List<String> patterns) =>
        patterns.any((r) => RegExp(r).hasMatch(u));
    if (has([
      r'space\.bilibili\.com',
      r'bilibili\.com/lists/',
      'b23.tv',
      r'bilibili\.com/video/',
      r'bilibili\.com/festival/',
    ])) {
      return 'bili';
    }
    if (has([
      r'youtube\.com/watch',
      r'youtube\.com/shorts',
      r'youtube\.com/live',
      r'youtu\.be/',
      r'youtube\.com/channel/',
      'youtube.com/@',
      r'youtube\.com/playlist',
    ])) {
      return 'youtube';
    }
    if (has([r'tiktok\.com', r'vm\.tiktok'])) return 'tiktok';
    if (has([
      'douyin.com',
      'v.douyin.com',
      'iesdouyin.com',
      'iesdouyin',
    ])) {
      return 'douyin';
    }
    return null;
  }

  Future<void> _pickSaveDir() async {
    final path = await App.showFolderPicker();
    if (path == null || !mounted) return;
    setState(() => _saveDir = path);
    _toast('本次下载将保存到：$path');
  }

  Future<void> _parseExternal() async {
    setState(() {
      _parsing = true;
      _preview = null;
      _ytPreview = null;
      _selectedHeight = null;
      _error = null;
    });
    try {
      final p = await App.client!.detectUrl(_inputController.text.trim());
      if (!mounted) return;
      if (p.hasError) {
        setState(() => _error = '${p.platformName} 解析失败：${p.error}');
        return;
      }
      setState(() => _ytPreview = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _downloadExternal() async {
    final p = _ytPreview;
    if (p == null) return;
    setState(() => _downloading = true);
    try {
      await App.client!.createYtdlpTask(
        url: _inputController.text.trim(),
        formatId: p.isBatch ? null : _selectedHeight,
        label: '${p.platformName}${p.isBatch ? '列表' : ''}下载',
        saveDir: _saveDir,
      );
      if (!mounted) return;
      _toast(
        '已添加到下载队列',
        actionLabel: widget.onGoTasks == null ? null : '查看任务',
        onAction: widget.onGoTasks,
      );
      _inputController.clear();
      setState(() {
        _ytPreview = null;
        _selectedHeight = null;
      });
    } catch (e) {
      if (!mounted) return;
      _toast('创建任务失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final text = await _readClipboardWithRetry();
      if (text == null || text.trim().isEmpty) {
        _toast('剪贴板为空或不含文本');
        return;
      }
      final trimmed = text.trim();
      _lastClipboard = trimmed;
      final current = _inputController.text;
      final selection = _inputController.selection;
      String newText;
      int newOffset;
      if (selection.isValid && selection.start >= 0 && selection.start != selection.end) {
        final before = current.substring(0, selection.start);
        final after = current.substring(selection.end);
        newText = '$before$trimmed$after';
        newOffset = before.length + trimmed.length;
      } else if (selection.isValid && selection.start >= 0) {
        final before = current.substring(0, selection.start);
        final after = current.substring(selection.start);
        if (_batchMode && current.isNotEmpty && before.isNotEmpty && !before.endsWith('\n')) {
          newText = '$before\n$trimmed$after';
          newOffset = before.length + 1 + trimmed.length;
        } else {
          newText = '$before$trimmed$after';
          newOffset = before.length + trimmed.length;
        }
      } else {
        newText = current.isEmpty ? trimmed : '$current\n$trimmed';
        newOffset = newText.length;
      }
      setState(() {
        _inputController.text = newText;
        _inputController.selection = TextSelection.collapsed(offset: newOffset);
      });
      _focusNode.requestFocus();
      _toast('已粘贴 ${trimmed.length} 字符');
    } catch (e) {
      _toast('粘贴失败：$e');
    }
  }

  List<String> _splitBatchInput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    // Try extract URLs first
    final urlReg = RegExp(r'https?://[^\s]+');
    final urls = urlReg.allMatches(trimmed).map((m) => m.group(0)!).toList();
    if (urls.length > 1) return urls;
    // Fallback: split by newline
    final lines = trimmed.split(RegExp(r'[\r\n]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (lines.length > 1) return lines;
    // Split by comma or Chinese comma
    if (trimmed.contains(',') || trimmed.contains('，')) {
      return trimmed.split(RegExp(r'[,，]+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [trimmed];
  }

  Future<void> _parse() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (_batchMode) {
      await _parseBatch();
      return;
    }
    final platform = _quickDetect(text);
    if (platform == 'bili' || platform == 'youtube') {
      await _parseExternal();
      return;
    }
    _lastTiktok = platform == 'tiktok';
    setState(() {
      _parsing = true;
      _preview = null;
      _ytPreview = null;
      _error = null;
    });
    try {
      var id = text;
      if (text.contains('http')) {
        final url = await App.client!.expandShareText(text, _lastTiktok);
        id = url != null ? (_extractIdFromUrl(url) ?? url) : text;
      } else {
        id = _extractIdFromUrl(text) ?? text;
      }
      final data = await App.client!.workDetail(id, _lastTiktok);
      final preview = WorkPreview.tryParse(data);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = preview == null ? '解析失败：未获取到作品数据，请检查链接或 Cookie 状态' : null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _parseBatch() async {
    final inputs = _splitBatchInput(_inputController.text);
    if (inputs.isEmpty) return;
    setState(() {
      _parsing = true;
      _error = null;
      _batchItems = inputs.map((t) => _BatchItem(text: t, status: _BatchStatus.pending)).toList();
    });
    for (var i = 0; i < inputs.length; i++) {
      final raw = inputs[i];
      setState(() => _batchItems[i] = _batchItems[i].copyWith(status: _BatchStatus.loading));
      try {
        final platform = _quickDetect(raw);
        if (platform == 'bili' || platform == 'youtube') {
          await App.client!.createYtdlpTask(
            url: raw,
            label: platform == 'bili' ? 'B站下载' : 'YouTube下载',
            saveDir: _saveDir,
          );
          if (!mounted) return;
          setState(() => _batchItems[i] = _batchItems[i].copyWith(status: _BatchStatus.success, message: '已加入队列'));
          continue;
        }
        final tiktok = platform == 'tiktok';
        var id = raw;
        if (raw.contains('http')) {
          final url = await App.client!.expandShareText(raw, tiktok);
          id = url != null ? (_extractIdFromUrl(url) ?? url) : raw;
        } else {
          id = _extractIdFromUrl(raw) ?? raw;
        }
        final data = await App.client!.workDetail(id, tiktok);
        if (data == null) throw Exception('未获取到数据');
        await App.client!.createDetailTask(tiktok: tiktok, data: data, saveDir: _saveDir);
        if (!mounted) return;
        setState(() => _batchItems[i] = _batchItems[i].copyWith(status: _BatchStatus.success, message: '已加入队列'));
      } catch (e) {
        if (!mounted) return;
        setState(() => _batchItems[i] = _batchItems[i].copyWith(status: _BatchStatus.failed, message: e.toString()));
      }
    }
    if (!mounted) return;
    setState(() => _parsing = false);
    _toast(
      '批量处理完成：${_batchItems.where((e) => e.status == _BatchStatus.success).length}/${_batchItems.length} 成功',
      actionLabel: widget.onGoTasks == null ? null : '查看任务',
      onAction: widget.onGoTasks,
    );
  }

  Future<void> _download() async {
    if (_preview == null) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await App.client!.createDetailTask(tiktok: _lastTiktok, data: _preview!.rawData, saveDir: _saveDir);
      if (!mounted) return;
      _toast(
        '已添加到下载队列',
        actionLabel: widget.onGoTasks == null ? null : '查看任务',
      onAction: widget.onGoTasks,
      );
      _inputController.clear();
      setState(() => _preview = null);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadSingleImage(int index) async {
    if (_preview == null) return;
    final urls = _preview!.imageUrls;
    if (index < 0 || index >= urls.length) return;
    setState(() => _downloading = true);
    try {
      final filtered = Map<String, dynamic>.from(_preview!.rawData);
      filtered['downloads'] = [urls[index]];
      filtered['static_cover'] = '';
      filtered['dynamic_cover'] = '';
      await App.client!.createDetailTask(tiktok: _lastTiktok, data: filtered, saveDir: _saveDir);
      if (!mounted) return;
      _toast(
        '已添加第 ${index + 1} 张图片到下载队列',
        actionLabel: widget.onGoTasks == null ? null : '查看任务',
      onAction: widget.onGoTasks,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CheckboxListTile(
              value: _batchMode,
              onChanged: (v) => setState(() => _batchMode = v ?? false),
              title: const Text('批量下载'),
              subtitle: const Text('每行一个链接，自动识别抖音/TikTok/B站/YouTube'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            const SizedBox(height: 4),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteFromClipboard,
                const SingleActivator(LogicalKeyboardKey.insert, shift: true): _pasteFromClipboard,
              },
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                maxLines: _batchMode ? 6 : 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _batchMode ? '批量作品链接（每行一个）' : '作品分享链接 / 口令 / 作品 ID',
                  hintText: _batchMode ? '支持粘贴多条分享文本，每行一条' : '自动识别抖音 / TikTok / B站 / YouTube 链接',
                  suffixIcon: IconButton(
                    tooltip: _batchMode ? '批量解析并下载' : '解析',
                    onPressed: _parsing ? null : _parse,
                    icon: _parsing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (_) => _parsing ? null : _parse(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('粘贴'),
                onPressed: _pasteFromClipboard,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('清空'),
                onPressed: () => setState(() {
                  _inputController.clear();
                  _preview = null;
                  _ytPreview = null;
                  _selectedHeight = null;
                  _error = null;
                  _batchItems = [];
                }),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.content_paste_search, size: 18),
                label: const Text('粘贴并解析'),
                onPressed: () async {
                  await _pasteFromClipboard();
                  if (_inputController.text.trim().isNotEmpty) await _parse();
                },
              ),
              SaveToChip(saveDir: _saveDir, onPick: _pickSaveDir, onClear: () => setState(() => _saveDir = null)),
            ]),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
                  ]),
                ),
              ),
            if (_batchMode && _batchItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('批量结果 (${_batchItems.length} 条)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _batchItems.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          _batchIcon(_batchItems[i].status),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_batchItems[i].text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                          const SizedBox(width: 8),
                          Text(_batchItems[i].message.isEmpty ? _statusLabel(_batchItems[i].status) : _batchItems[i].message,
                              style: Theme.of(context).textTheme.labelSmall),
                        ]),
                      ),
                  ]),
                ),
              ),
            ],
            if (!_batchMode && _ytPreview != null) ...[
              _YtdlpPreviewCard(
                preview: _ytPreview!,
                selectedHeight: _selectedHeight,
                onHeightChanged: (h) => setState(() => _selectedHeight = h),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: _downloading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_ytPreview!.isBatch ? Icons.playlist_add_check : Icons.download),
                label: Text(_ytPreview!.isBatch
                    ? '下载全部${_ytPreview!.itemCount != null ? '（共 ${_ytPreview!.itemCount} 个）' : ''}'
                    : '下载该视频'),
                onPressed: _downloading ? null : _downloadExternal,
              ),
            ],
            if (!_batchMode && _preview != null) ...[
              _PreviewCard(preview: _preview!),
              const SizedBox(height: 12),
              if (_preview!.isGallery) ...[
                _GalleryGrid(preview: _preview!, onDownloadSingle: _downloadSingleImage, downloading: _downloading),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: _downloading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download),
                      label: const Text('下载全部'),
                      onPressed: _downloading ? null : _download,
                    ),
                  ),
                ]),
              ] else ...[
                FilledButton.icon(
                  icon: _downloading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: const Text('下载该作品'),
                  onPressed: _downloading ? null : _download,
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _batchIcon(_BatchStatus s) {
    return switch (s) {
      _BatchStatus.pending => const Icon(Icons.schedule, size: 16, color: Colors.grey),
      _BatchStatus.loading => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      _BatchStatus.success => const Icon(Icons.check_circle, size: 16, color: Colors.green),
      _BatchStatus.failed => const Icon(Icons.error, size: 16, color: Colors.red),
    };
  }

  String _statusLabel(_BatchStatus s) => switch (s) {
        _BatchStatus.pending => '等待',
        _BatchStatus.loading => '处理中',
        _BatchStatus.success => '成功',
        _BatchStatus.failed => '失败',
      };
}

enum _BatchStatus { pending, loading, success, failed }

class _BatchItem {
  final String text;
  final _BatchStatus status;
  final String message;
  const _BatchItem({required this.text, required this.status, this.message = ''});
  _BatchItem copyWith({_BatchStatus? status, String? message}) => _BatchItem(text: text, status: status ?? this.status, message: message ?? this.message);
}

class _PreviewCard extends StatelessWidget {
  final WorkPreview preview;
  const _PreviewCard({required this.preview});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 120,
            height: 160,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: preview.coverUrl.isEmpty
                ? const Icon(Icons.video_library_outlined)
                : Image.network(preview.coverUrl,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
                child: Text(preview.isGallery ? '图集' : '视频', style: Theme.of(context).textTheme.labelSmall),
              ),
              if (preview.isGallery) ...[
                const SizedBox(width: 6),
                Text('${preview.imageUrls.length} 张', style: Theme.of(context).textTheme.labelSmall),
              ]
            ]),
            const SizedBox(height: 8),
            Text(preview.title, maxLines: 4, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (preview.author.isNotEmpty) Text('作者：${preview.author}', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
      ),
    );
  }
}

class _YtdlpPreviewCard extends StatelessWidget {
  final YtdlpPreview preview;
  final String? selectedHeight;
  final ValueChanged<String?> onHeightChanged;

  const _YtdlpPreviewCard({
    required this.preview,
    required this.selectedHeight,
    required this.onHeightChanged,
  });

  Color get _platformColor =>
      preview.platform == 'bili' ? const Color(0xFFFB7299) : const Color(0xFFFF0000);

  String _fmtDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m分${s.toString().padLeft(2, '0')}秒';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 120,
              height: preview.isBatch ? 90 : 90,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: preview.thumbnail.isEmpty
                  ? Icon(preview.platform == 'bili'
                      ? Icons.live_tv_outlined
                      : Icons.ondemand_video_outlined)
                  : Image.network(preview.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_not_supported_outlined)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: _platformColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(preview.platformName,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _platformColor)),
                  ),
                  if (preview.isBatch) ...[
                    const SizedBox(width: 6),
                    Text('列表 · 共 ${preview.itemCount ?? '?'} 个',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                  if (!preview.isBatch && _fmtDuration(preview.duration).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(_fmtDuration(preview.duration),
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ]),
                const SizedBox(height: 8),
                Text(
                  preview.title.isEmpty ? '（无标题）' : preview.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (preview.uploader.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('UP主/频道：${preview.uploader}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ]),
            ),
          ]),
          if (!preview.isBatch && preview.formats.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedHeight ?? '',
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '画质选择',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('最高画质（自动）')),
                ...preview.formats.map((f) => DropdownMenuItem(
                      value: f.height.toString(),
                      child: Text(f.label +
                          (f.filesize != null && f.filesize! > 0
                              ? ' · ${(f.filesize! / 1024 / 1024).toStringAsFixed(0)}MB'
                              : '')),
                    )),
              ],
              onChanged: (v) => onHeightChanged(v == '' ? null : v),
            ),
          ],
          if (preview.isBatch && preview.sampleTitles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('内容预览', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final t in preview.sampleTitles.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  const Icon(Icons.play_circle_outline, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(t,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
            if ((preview.itemCount ?? 0) > 5)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('…等 ${preview.itemCount} 个条目',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
          ],
        ]),
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  final WorkPreview preview;
  final Future<void> Function(int) onDownloadSingle;
  final bool downloading;
  const _GalleryGrid({required this.preview, required this.onDownloadSingle, required this.downloading});

  @override
  Widget build(BuildContext context) {
    final images = preview.imageUrls;
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('图集预览（点击下载单张）', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.75),
        itemCount: images.length,
        itemBuilder: (context, i) {
          final url = images[i];
          return InkWell(
            onTap: downloading ? null : () => onDownloadSingle(i),
            borderRadius: BorderRadius.circular(8),
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.surfaceContainerHighest),
                clipBehavior: Clip.antiAlias,
                child: url.isEmpty
                    ? const Center(child: Icon(Icons.image))
                    : Image.network(url, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
              ),
              Positioned(top: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)))),
              Positioned(bottom: 4, right: 4, child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(4), child: const Icon(Icons.download, size: 14, color: Colors.white))),
            ]),
          );
        },
      ),
    ]);
  }
}
