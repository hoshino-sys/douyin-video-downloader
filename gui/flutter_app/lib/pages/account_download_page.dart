import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../services/toast.dart';
import '../widgets/save_to_chip.dart';

void _toast(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  AppToast.show(context, message, actionLabel: actionLabel, onAction: onAction);
}

class AccountDownloadPage extends StatefulWidget {
  final VoidCallback? onGoTasks;
  const AccountDownloadPage({super.key, this.onGoTasks});

  @override
  State<AccountDownloadPage> createState() => _AccountDownloadPageState();
}

class _AccountDownloadPageState extends State<AccountDownloadPage> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  String _tab = 'post';
  DateTime? _earliest;
  DateTime? _latest;
  bool _submitting = false;
  String? _saveDir;

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _isTiktokInput(String input) =>
      input.toLowerCase().contains('tiktok.com');

  String? _extractSecUserId(String input) {
    for (final pattern in [
      RegExp(r'sec_uid=([a-zA-Z0-9_-]+)'),
      RegExp(r'/user/([a-zA-Z0-9_-]{20,})'),
    ]) {
      final match = pattern.firstMatch(input);
      if (match != null) return match.group(1);
    }
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(trimmed)) return trimmed;
    return null;
  }

  Future<void> _submit() async {
    final text = _inputController.text.trim();
    if (text.isNotEmpty) {
      final detected = text.toLowerCase().contains('tiktok.com')
          ? 'tiktok'
          : (text.contains('douyin.com') ||
                  text.contains('iesdouyin') ||
                  RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(text)
              ? 'douyin'
              : null);
      if (detected == null) {
        _toast(context, 'B站/YouTube 批量下载请使用「链接下载」页粘贴空间或频道链接');
        return;
      }
    }
    final secUserId = _extractSecUserId(text);
    if (secUserId == null) {
      _toast(context, '无法识别账号链接，请输入账号主页链接或 sec_user_id');
      return;
    }
    setState(() => _submitting = true);
    try {
      await App.client!.createAccountTask(
        tiktok: _isTiktokInput(text),
        secUserId: secUserId,
        tab: _tab,
        earliest: _earliest == null ? '' : _formatDate(_earliest!),
        latest: _latest == null ? '' : _formatDate(_latest!),
        saveDir: _saveDir,
      );
      if (!mounted) return;
      _toast(
        context,
        '任务已创建，正在后台下载…',
        actionLabel: widget.onGoTasks == null ? null : '查看任务',
        onAction: widget.onGoTasks,
      );
      _inputController.clear();
    } catch (e) {
      if (!mounted) return;
      _toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickSaveDir() async {
    final path = await App.showFolderPicker();
    if (path == null || !mounted) return;
    setState(() => _saveDir = path);
    _toast(context, '本次下载将保存到：$path');
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      String? text = data?.text;
      text ??= (await Clipboard.getData('text/plain'))?.text;
      if (text == null || text.trim().isEmpty) {
        if (mounted) _toast(context, '剪贴板为空');
        return;
      }
      final trimmed = text.trim();
      setState(() => _inputController.text = trimmed);
      _focusNode.requestFocus();
      if (mounted) _toast(context, '已粘贴 ${trimmed.length} 字符');
    } catch (e) {
      if (mounted) _toast(context, '粘贴失败：$e');
    }
  }

  Future<void> _pickDate(bool isEarliest) async {
    final initial = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2016),
      lastDate: initial,
    );
    if (picked != null) {
      setState(() {
        if (isEarliest) {
          _earliest = picked;
        } else {
          _latest = picked;
        }
      });
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
              Text('自动识别抖音 / TikTok 账号链接；B站/YouTube 批量下载请使用「链接下载」页粘贴空间或频道链接',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
                  const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteFromClipboard,
                  const SingleActivator(LogicalKeyboardKey.insert, shift: true): _pasteFromClipboard,
                },
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '账号主页链接 / sec_user_id',
                    hintText: '支持抖音与 TikTok 账号主页链接，自动识别平台',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(icon: const Icon(Icons.content_paste, size: 18), label: const Text('粘贴'), onPressed: _pasteFromClipboard),
                OutlinedButton.icon(icon: const Icon(Icons.clear, size: 18), label: const Text('清空'), onPressed: () => setState(() => _inputController.clear())),
                SaveToChip(saveDir: _saveDir, onPick: _pickSaveDir, onClear: () => setState(() => _saveDir = null)),
              ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _tab,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '作品类型',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'post', child: Text('发布的作品')),
                        DropdownMenuItem(value: 'favorite', child: Text('喜欢的作品')),
                      ],
                      onChanged: (v) =>
                          setState(() => _tab = v ?? 'post'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('发布日期范围（可选，用于筛选作品）',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(_earliest == null
                          ? '最早日期'
                          : _formatDate(_earliest!)),
                      onPressed: () => _pickDate(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('至'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label:
                          Text(_latest == null ? '最晚日期' : _formatDate(_latest!)),
                      onPressed: () => _pickDate(false),
                    ),
                  ),
                  IconButton(
                    tooltip: '清除日期',
                    onPressed: (_earliest == null && _latest == null)
                        ? null
                        : () =>
                            setState(() { _earliest = null; _latest = null; }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_add_check),
                label: const Text('开始批量下载'),
                onPressed: _submitting ? null : _submit,
              ),
              const SizedBox(height: 8),
              Text(
                '说明：任务将在后台逐个请求并下载作品，耗时取决于作品数量，可随时在「任务」页查看状态。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
