import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
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
        title: const Text('DouK 下载器'),
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
            ],
          ),
        ),
      ),
    );
  }
}
