import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../services/toast.dart';
import '../widgets/platform_badge.dart';
import 'account_download_page.dart';
import 'link_download_page.dart';
import 'onboarding_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';

class HomeShell extends StatefulWidget {
  final bool cookieLoggedIn;

  const HomeShell({super.key, required this.cookieLoggedIn});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _cookieBannerDismissed = false;
  CookieStatus? _cookieStatus;
  bool _updateAvailable = false;
  late bool _cookieLoggedIn;

  @override
  void initState() {
    super.initState();
    _cookieLoggedIn = widget.cookieLoggedIn;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCookie();
      _startupUpdateCheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    App.reset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      App.backend?.kill();
    }
  }

  bool get _cookieBannerVisible =>
      !_cookieBannerDismissed && !(_cookieStatus?.allImported ?? false);

  /// 启动时后台静默检查更新，发现新版本轻提示一次
  Future<void> _startupUpdateCheck() async {
    try {
      final info = await App.client!.updateCheck();
      if (!mounted || !info.updateAvailable) return;
      setState(() => _updateAvailable = true);
      AppToast.show(
        context,
        '发现新版本 v${info.latest}，可在「设置」中下载更新',
        duration: const Duration(seconds: 5),
      );
    } catch (_) {}
  }

  Future<void> _checkCookie() async {
    try {
      final status = await App.client!.cookieStatus();
      if (!mounted) return;
      setState(() {
        _cookieStatus = status;
        _cookieLoggedIn = status.loggedIn;
      });
    } catch (_) {}
  }

  Future<void> _openWizard() async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OnboardingPage(info: const BootstrapInfo(
        version: '',
        disclaimerAccepted: true,
        cookieConfigured: false,
        cookieLoggedIn: false,
      )),
    ));
    _checkCookie();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LinkDownloadPage(onGoTasks: () => setState(() => _index = 2)),
      AccountDownloadPage(onGoTasks: () => setState(() => _index = 2)),
      TasksPage(key: ValueKey(_cookieBannerVisible)),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: const Text('夜星视频下载器'),
        actions: [
          IconButton(
            tooltip: 'Cookie 状态',
            icon: Icon(
              _cookieLoggedIn ? Icons.verified_user : Icons.key_off_outlined,
              color: _cookieLoggedIn ? Colors.green : null,
            ),
            onPressed: _showCookieSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_cookieBannerVisible)
            MaterialBanner(
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key_off_outlined,
                          size: 18, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 6),
                      Text('Cookie 导入状态',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(
                        '未导入的平台无法使用对应下载功能，点击图标去导入',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in _kCookiePlatforms)
                        _platformStateChip(context, key),
                    ],
                  ),
                ],
              ),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35),
              actions: [
                TextButton(onPressed: _openWizard, child: const Text('去导入')),
                TextButton(
                  onPressed: () =>
                      setState(() => _cookieBannerDismissed = true),
                  child: const Text('关闭'),
                ),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.link),
                      selectedIcon: Icon(Icons.link),
                      label: Text('链接下载'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.person),
                      selectedIcon: Icon(Icons.person),
                      label: Text('账号下载'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download_for_offline_outlined),
                      label: Text('任务'),
                    ),
                    NavigationRailDestination(
                      icon: Badge(
                        isLabelVisible: _updateAvailable,
                        smallSize: 8,
                        child: const Icon(Icons.settings_outlined),
                      ),
                      selectedIcon: const Icon(Icons.settings),
                      label: const Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 状态条上的四个平台（固定顺序）
  static const List<String> _kCookiePlatforms = [
    'douyin', 'tiktok', 'bili', 'youtube',
  ];

  Widget _platformStateChip(BuildContext ctx, String key) {
    final meta = platformMeta(key);
    final state = _cookieStatus?.platforms[key];
    final imported = state?.imported ?? false;
    final loggedIn = state?.loggedIn ?? false;
    final color = imported
        ? (loggedIn ? Colors.green : const Color(0xFFE6A23C))
        : Theme.of(ctx).colorScheme.outline;
    final label = imported
        ? (loggedIn ? '已导入' : '已导入·未登录')
        : '未导入';
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: imported ? null : _openWizard,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              imported ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(meta.label,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.0,
                    fontWeight: FontWeight.w600,
                    color: color)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 11, height: 1.0, color: color)),
            if (!imported) ...[
              const SizedBox(width: 2),
              Icon(Icons.add_circle_outline, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }

  void _showCookieSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(_cookieLoggedIn ? Icons.check_circle : Icons.error_outline,
                    color: _cookieLoggedIn
                        ? Colors.green
                        : Theme.of(ctx).colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  _cookieLoggedIn
                      ? 'Cookie 已配置且处于登录状态'
                      : 'Cookie 未配置或未登录',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in _kCookiePlatforms)
                    _platformStateChip(ctx, key),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openWizard();
                },
                child: const Text('重新配置 Cookie'),
              ),
              const SizedBox(height: 20),
              Text('一键导入（抖音/TikTok/B站/YouTube，失败项仅提示）',
                  style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('一键导入全部 Cookie'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _importAllCookies();
                },
              ),
              const SizedBox(height: 20),
              Text('单独导入（可选，用于对应平台下载）',
                  style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.live_tv_outlined, size: 18),
                    label: const Text('导入B站 Cookie'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _importPlatformCookie('bili');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.ondemand_video_outlined, size: 18),
                    label: const Text('导入YouTube Cookie'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _importPlatformCookie('youtube');
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importAllCookies() async {
    List<String> browsers;
    try {
      browsers = await App.client!.cookieBrowsers();
    } catch (e) {
      if (mounted) AppToast.show(context, '获取浏览器列表失败：$e', success: false);
      return;
    }
    if (!mounted) return;
    final browser = await _pickBrowserDialog('一键导入全部平台 Cookie', browsers);
    if (browser == null || !mounted) return;
    AppToast.show(context, '正在读取浏览器 Cookie（四个平台）…',
        duration: const Duration(seconds: 20));
    try {
      final result = await App.client!.cookieFromBrowserAll(browser);
      if (!mounted) return;
      AppToast.show(
        context,
        result.success ? '导入完成：${result.summary()}' : '导入失败：${result.summary()}',
        success: result.success,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (mounted) AppToast.show(context, '导入失败：$e', success: false);
    }
    _checkCookie();
  }

  Future<String?> _pickBrowserDialog(
      String title, List<String> browsers) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (browsers.isEmpty) const Text('未获取到支持的浏览器列表'),
              for (final b in browsers)
                ListTile(
                  title: Text(b),
                  onTap: () => Navigator.pop(ctx, b),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Future<void> _importPlatformCookie(String target) async {
    final platformName = target == 'bili' ? 'B站' : 'YouTube';
    List<String> browsers;
    try {
      browsers = await App.client!.cookieBrowsers();
    } catch (e) {
      if (mounted) AppToast.show(context, '获取浏览器列表失败：$e', success: false);
      return;
    }
    if (!mounted) return;
    final browser = await _pickBrowserDialog('选择已登录$platformName的浏览器', browsers);
    if (browser == null || !mounted) return;
    AppToast.show(context, '正在读取$platformName Cookie…', duration: const Duration(seconds: 10));
    try {
      final result =
          await App.client!.cookieFromBrowser(browser, target: target);
      if (!mounted) return;
      if (!result.success) {
        AppToast.show(context, result.message, success: false);
      } else if (result.loggedIn) {
        AppToast.show(context, '$platformName Cookie 导入成功（已检测到登录态）');
      } else {
        AppToast.show(
          context,
          '$platformName Cookie 已写入，但未检测到登录态：'
          '请先在浏览器登录$platformName并完全关闭浏览器后重新导入',
          success: false,
        );
      }
    } catch (e) {
      if (mounted) AppToast.show(context, '导入失败：$e', success: false);
    }
    _checkCookie();
  }
}
