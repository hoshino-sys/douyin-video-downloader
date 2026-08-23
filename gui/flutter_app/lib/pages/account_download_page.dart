import 'package:flutter/material.dart';

import '../app.dart';

class AccountDownloadPage extends StatefulWidget {
  final VoidCallback? onGoTasks;
  const AccountDownloadPage({super.key, this.onGoTasks});

  @override
  State<AccountDownloadPage> createState() => _AccountDownloadPageState();
}

class _AccountDownloadPageState extends State<AccountDownloadPage> {
  bool _tiktok = false;
  final _inputController = TextEditingController();
  String _tab = 'post';
  DateTime? _earliest;
  DateTime? _latest;
  bool _submitting = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

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
    final secUserId = _extractSecUserId(_inputController.text);
    if (secUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('无法识别账号链接，请输入账号主页链接或 sec_user_id'),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      await App.client!.createAccountTask(
        tiktok: _tiktok,
        secUserId: secUserId,
        tab: _tab,
        earliest: _earliest == null ? '' : _formatDate(_earliest!),
        latest: _latest == null ? '' : _formatDate(_latest!),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('任务已创建，正在后台下载…'),
        action: widget.onGoTasks == null ? null : SnackBarAction(label: '查看任务', onPressed: widget.onGoTasks!),
      ));
      _inputController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('抖音')),
                  ButtonSegment(value: true, label: Text('TikTok')),
                ],
                selected: {_tiktok},
                onSelectionChanged: (s) => setState(() => _tiktok = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '账号主页链接 / sec_user_id',
                  hintText: '例如：https://www.douyin.com/user/MS4wLjABAAAA…',
                ),
              ),
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
