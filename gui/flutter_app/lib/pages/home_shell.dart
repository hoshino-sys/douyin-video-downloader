import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../services/toast.dart';
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
  bool _cookieBannerVisible = false;
  late bool _cookieLoggedIn;

  @override
  void initState() {
    super.initState();
    _cookieLoggedIn = widget.cookieLoggedIn;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCookie());
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

  Future<void> _checkCookie() async {
    try {
      final status = await App.client!.cookieStatus();
      if (!mounted) return;
      setState(() {
        _cookieBannerVisible = !status.configured;
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
              content: const Text('尚未配置 Cookie，部分功能不可用。点击右侧按钮完成配置。'),
              leading: const Icon(Icons.warning_amber_rounded),
              backgroundColor:
                  Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
              actions: [
                TextButton(onPressed: _openWizard, child: const Text('去配置')),
                TextButton(
                  onPressed: () => setState(() => _cookieBannerVisible = false),
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
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.link),
                      selectedIcon: Icon(Icons.link),
                      label: Text('链接下载'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person),
                      selectedIcon: Icon(Icons.person),
                      label: Text('账号下载'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download_for_offline_outlined),
                      label: Text('任务'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
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
  }
}
