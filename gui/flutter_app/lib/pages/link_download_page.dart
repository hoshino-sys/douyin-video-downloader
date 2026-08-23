import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';

class LinkDownloadPage extends StatefulWidget {
  final VoidCallback? onGoTasks;

  const LinkDownloadPage({super.key, this.onGoTasks});

  @override
  State<LinkDownloadPage> createState() => _LinkDownloadPageState();
}

class _LinkDownloadPageState extends State<LinkDownloadPage> {
  bool _tiktok = false;
  final _inputController = TextEditingController();
  bool _parsing = false;
  bool _downloading = false;
  WorkPreview? _preview;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
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

  Future<void> _parse() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _parsing = true;
      _preview = null;
      _error = null;
    });
    try {
      var id = text;
      if (text.contains('http')) {
        final url = await App.client!.expandShareText(text, _tiktok);
        id = url != null ? (_extractIdFromUrl(url) ?? url) : text;
      } else {
        id = _extractIdFromUrl(text) ?? text;
      }
      final data = await App.client!.workDetail(id, _tiktok);
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

  Future<void> _download() async {
    if (_preview == null) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await App.client!.createDetailTask(
        tiktok: _tiktok,
        data: _preview!.rawData,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已添加到下载队列'),
        action: widget.onGoTasks == null
            ? null
            : SnackBarAction(label: '查看任务', onPressed: widget.onGoTasks!),
      ));
      _inputController.clear();
      setState(() => _preview = null);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('抖音')),
                  ButtonSegment(value: true, label: Text('TikTok')),
                ],
                selected: {_tiktok},
                onSelectionChanged: (s) =>
                    setState(() => _tiktok = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _inputController,
                maxLines: 3,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: '作品分享链接 / 口令 / 作品 ID',
                  hintText: '支持粘贴分享文本，自动提取链接',
                  suffixIcon: IconButton(
                    tooltip: '解析',
                    onPressed: _parsing ? null : _parse,
                    icon: _parsing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (_) => _parsing ? null : _parse(),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                    ]),
                  ),
                ),
              if (_preview != null) ...[
                _PreviewCard(preview: _preview!),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: const Text('下载该作品'),
                  onPressed: _downloading ? null : _download,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 160,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: preview.coverUrl.isEmpty
                  ? const Icon(Icons.video_library_outlined)
                  : Image.network(
                      preview.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_not_supported_outlined),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        preview.isGallery ? '图集' : '视频',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    preview.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  if (preview.author.isNotEmpty)
                    Text('作者：${preview.author}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
