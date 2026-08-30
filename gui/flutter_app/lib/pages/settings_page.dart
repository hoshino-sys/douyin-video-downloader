import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../services/theme_controller.dart';
import '../services/toast.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _data = {};
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _savedHint;
  String _version = '';
  UpdateCheckInfo? _update;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
    _checkUpdate(silent: true);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key, String fallback) {
    return _controllers.putIfAbsent(key, () => TextEditingController(text: fallback));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await App.client!.settings();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await App.client!.bootstrap();
      if (!mounted) return;
      setState(() => _version = info.version);
    } catch (_) {}
  }

  Future<void> _checkUpdate({bool silent = false}) async {
    setState(() => _checkingUpdate = true);
    try {
      final info = await App.client!.updateCheck();
      if (!mounted) return;
      setState(() => _update = info);
      if (!silent) {
        if (info.hasError) {
          AppToast.show(context, info.error, success: false);
        } else if (!info.updateAvailable) {
          AppToast.show(context, '已是最新版本 v${info.current}');
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        AppToast.show(context, '检查更新失败：$e', success: false);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _confirmUpdate() async {
    final info = _update;
    if (info == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${info.latest}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本：v${info.current}'),
            const SizedBox(height: 4),
            Text('最新版本：v${info.latest}'),
            if (info.zipUrl.isEmpty) ...[
              const SizedBox(height: 12),
              Text('未在发布页找到可下载的更新包，请到发布页手动下载：\n${info.pageUrl}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ] else ...[
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      info.notes,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '点击「在应用内下载」开始下载更新包（可在任务页查看进度）；'
                '下载完成后退出本程序，解压压缩包覆盖原目录即可完成更新。',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          if (info.zipUrl.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('在应用内下载'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await App.client!.updateDownload(info.zipUrl);
      if (!mounted) return;
      AppToast.show(context, '已开始下载更新包，可在「任务」页查看进度');
    } catch (e) {
      if (mounted) AppToast.show(context, '创建下载任务失败：$e', success: false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _savedHint = null;
    });
    try {
      final payload = Map<String, dynamic>.from(_data);
      for (final k in _textKeys) {
        payload[k] = (_controllers[k]?.text ?? '').trim();
      }
      for (final k in _intKeys) {
        final text = (_controllers[k]?.text ?? '').trim();
        if (text.isEmpty) {
          payload[k] = null;
        } else {
          final v = int.tryParse(text);
          if (v == null) throw Exception('「$k」需要填写整数');
          payload[k] = v;
        }
      }
      final storage = _controllers['storage_format']?.text.trim() ?? '';
      payload['storage_format'] = storage.isEmpty ? '' : storage;
      await App.client!.saveSettings(payload);
      if (!mounted) return;
      setState(() => _savedHint = '保存成功');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _textKeys = [
    'root',
    'name_format',
    'date_format',
    'split',
    'proxy',
    'proxy_tiktok',
    'ffmpeg',
    'live_qualities',
  ];

  static const _intKeys = [
    'max_retry',
    'timeout',
    'chunk',
    'max_pages',
    'max_size',
    'truncate',
    'desc_length',
    'name_length',
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败：$_error'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _load, child: const Text('重试')),
        ]),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionHeader(context, Icons.palette_outlined, '界面外观'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('主题模式', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: themeController,
                    builder: (context, _) => SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
                        ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode)),
                        ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode)),
                      ],
                      selected: {themeController.mode},
                      onSelectionChanged: (s) => themeController.setMode(s.first),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('默认跟随系统，重启后生效', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, Icons.info_outline, '关于'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.smart_display_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('夜星视频下载器',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            _version.isEmpty
                                ? '版本号获取中…'
                                : (_update?.updateAvailable == true
                                    ? '版本 $_version（可更新到 ${_update!.latest}）'
                                    : '版本 $_version'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_checkingUpdate)
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                    else if (_update?.updateAvailable == true)
                      FilledButton.icon(
                        icon: const Icon(Icons.system_update_alt, size: 18),
                        label: Text('更新到 ${_update!.latest}'),
                        onPressed: _confirmUpdate,
                      )
                    else
                      OutlinedButton(
                        onPressed: () => _checkUpdate(),
                        child: const Text('检查更新'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, Icons.folder_outlined, '存储与命名'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _textField('root', '下载根目录', '例如 D:\\Downloads，留空使用软件目录下的 Downloads 文件夹'),
                  _textField('name_format', '文件命名格式', '可用变量：create_time type nickname desc id 等，空格分隔'),
                  Row(children: [
                    Expanded(child: _textField('date_format', '日期格式', '%Y-%m-%d %H:%M:%S')),
                    const SizedBox(width: 12),
                    Expanded(child: _textField('split', '分隔符', '默认 -')),
                  ]),
                  _boolTile('platform_folders',
                      '按平台分类保存（抖音/TikTok/B站/YouTube 子文件夹）',
                      fallback: true),
                  _boolTile('folder_mode', '为每个作品创建单独文件夹'),
                  const Divider(),
                  Row(children: [
                    Expanded(child: _intField('truncate', '文件名显示截断长度')),
                    const SizedBox(width: 12),
                    Expanded(child: _intField('desc_length', '描述截断长度')),
                  ]),
                  _intField('name_length', '文件名最大长度'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _storageValue(),
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '数据保存格式', helperText: '留空表示不保存额外数据文件'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('不保存')),
                      DropdownMenuItem(value: 'csv', child: Text('CSV')),
                      DropdownMenuItem(value: 'xlsx', child: Text('Excel (xlsx)')),
                      DropdownMenuItem(value: 'sql', child: Text('SQLite (sql)')),
                    ],
                    onChanged: (v) => _controllers['storage_format']?.text = v ?? '',
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, Icons.download_outlined, '下载内容'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  _boolTile('download', '下载作品文件（视频/图集）'),
                  _boolTile('music', '下载音乐/音频'),
                  _boolTile('dynamic_cover', '下载动态封面'),
                  _boolTile('static_cover', '下载静态封面'),
                  const Divider(),
                  Row(children: [
                    Expanded(child: _intField('max_size', '单文件大小上限（字节，0 不限）')),
                    const SizedBox(width: 12),
                    Expanded(child: _intField('chunk', '分块大小（字节）')),
                  ]),
                  _textField('live_qualities', '直播清晰度', '例如 origin, sd, ld, md'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, Icons.wifi_outlined, '网络与限流'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _textField('proxy', '抖音代理', '例如 http://127.0.0.1:7890，留空不使用'),
                  _textField('proxy_tiktok', 'TikTok 代理', '留空不使用'),
                  _textField('ffmpeg', 'FFmpeg 路径', '留空自动查找'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _intField('timeout', '请求超时（秒）')),
                    const SizedBox(width: 12),
                    Expanded(child: _intField('max_retry', '失败重试次数')),
                  ]),
                  Row(children: [
                    Expanded(child: _intField('max_pages', '账号最大请求页数')),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('保存设置'),
                onPressed: _saving ? null : _save,
              ),
              if (_savedHint != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 4),
                Text(_savedHint!),
              ],
              if (_error != null) ...[
                const SizedBox(width: 12),
                Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            ]),
            const SizedBox(height: 12),
            Text('提示：Cookie 请在右上角钥匙图标中管理（支持抖音/TikTok/B站/YouTube）；以下为抖音/TikTok 下载设置，B站/YouTube 下载使用系统网络设置；部分设置需重启下载任务后生效。',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _textField(String key, String label, String helper) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c(key, _stringValue(key)),
        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label, helperText: helper),
      ),
    );
  }

  Widget _intField(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _c(key, _intValue(key)),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
      ),
    );
  }

  Widget _boolTile(String key, String title, {bool fallback = false}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: _boolValue(key, fallback: fallback),
      onChanged: (v) => setState(() => _data[key] = v),
    );
  }

  String _stringValue(String key) {
    final v = _data[key];
    if (v is List) return v.join(' ');
    return v?.toString() ?? '';
  }

  String _storageValue() {
    final v = _data['storage_format']?.toString() ?? '';
    if (['', 'csv', 'xlsx', 'sql'].contains(v)) return v;
    _controllers.putIfAbsent('storage_format', () => TextEditingController(text: v));
    return '';
  }

  String _intValue(String key) {
    final v = _data[key];
    return v == null ? '' : v.toString();
  }

  bool _boolValue(String key, {bool fallback = false}) =>
      _data[key] as bool? ?? fallback;
}
