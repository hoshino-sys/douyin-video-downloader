import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import 'home_shell.dart';

class OnboardingPage extends StatefulWidget {
  final BootstrapInfo info;

  const OnboardingPage({super.key, required this.info});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late int _step;
  bool _agreed = false;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _step = widget.info.disclaimerAccepted ? 1 : 0;
  }

  void _next() => setState(() {
        _error = null;
        _step += 1;
      });

  Future<void> _acceptDisclaimer() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await App.client!.acceptDisclaimer();
      if (!mounted) return;
      _next();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _finish() async {
    final status = await App.client!.cookieStatus();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HomeShell(cookieLoggedIn: status.loggedIn),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (_step) {
                0 => _buildDisclaimer(context),
                _ => CookieSetupStep(
                    onDone: _finish,
                    onBack: () => setState(
                        () => _step = widget.info.disclaimerAccepted ? 1 : 0),
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.gavel_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('欢迎使用 DouK 下载器',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _disclaimerBody(context))),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('我已仔细阅读并同意以上免责声明'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: (_agreed && !_accepting) ? _acceptDisclaimer : null,
                  child: _accepting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('继续'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _disclaimerBody(BuildContext context) {
  const items = <String>[
    '使用者对本项目的使用由使用者自行决定，并自行承担风险。作者对使用者使用本项目所产生的任何损失、责任、或风险概不负责。',
    '本项目的作者提供的代码和功能是基于现有知识和技术的开发成果。作者按现有技术水平努力确保代码的正确性和安全性，但不保证代码完全没有错误或缺陷。',
    '本项目依赖的所有第三方库、插件或服务各自遵循其原始开源或商业许可，使用者需自行查阅并遵守相应协议。',
    '使用者在使用本项目时必须严格遵守 GNU General Public License v3.0 的要求。',
    '使用者在使用本项目的代码和功能时，必须自行研究相关法律法规，并确保其使用行为合法合规。任何因违反法律法规而导致的法律责任和风险，均由使用者自行承担。',
    '使用者不得使用本工具从事任何侵犯知识产权的行为，包括但不限于未经授权下载、传播受版权保护的内容。',
    '本项目不对使用者涉及的数据收集、存储、传输等处理活动的合规性承担责任。',
    '在任何情况下均不得将本项目的作者、贡献者或其他相关方与使用者的使用行为联系起来。',
    '基于本项目进行的任何二次开发、修改或编译的程序与原创作者无关，原创作者不承担与二次开发行为或其结果相关的任何责任。',
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('免责声明', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${i + 1}. ${items[i]}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      const SizedBox(height: 4),
      Text(
        '在使用本项目的代码和功能之前，请您认真考虑并接受以上免责声明。如果您使用了本项目的代码和功能，则视为您已完全理解并接受上述免责声明，并自愿承担使用本项目的一切风险和后果。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class CookieSetupStep extends StatefulWidget {
  final VoidCallback onDone;
  final VoidCallback onBack;

  const CookieSetupStep({super.key, required this.onDone, required this.onBack});

  @override
  State<CookieSetupStep> createState() => _CookieSetupStepState();
}

enum _Method { pick, browser, paste }

class _CookieSetupStepState extends State<CookieSetupStep> {
  _Method _method = _Method.pick;
  List<String> _browsers = [];
  String? _selectedBrowser;
  bool _extracting = false;
  String? _error;
  final _pasteController = TextEditingController();
  bool _pasting = false;

  @override
  void initState() {
    super.initState();
    _loadBrowsers();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _loadBrowsers() async {
    try {
      final browsers = await App.client!.cookieBrowsers();
      if (!mounted) return;
      setState(() => _browsers = browsers);
    } catch (_) {}
  }

  Future<void> _extractFromBrowser(String browser) async {
    setState(() {
      _selectedBrowser = browser;
      _extracting = true;
      _error = null;
    });
    try {
      final result = await App.client!.cookieFromBrowser(browser);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.message);
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _submitPaste() async {
    setState(() {
      _pasting = true;
      _error = null;
    });
    try {
      final result = await App.client!.cookiePaste(_pasteController.text);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.message);
      } else {
        widget.onDone();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                BackButton(onPressed: widget.onBack),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('配置抖音 Cookie',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                TextButton(
                  onPressed: () async {
                    final skip = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('跳过 Cookie 配置？'),
                        content: const Text('未配置 Cookie 时部分功能可能无法正常使用，可稍后在设置中重新配置。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('跳过')),
                        ],
                      ),
                    );
                    if (skip == true) widget.onDone();
                  },
                  child: const Text('跳过'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: switch (_method) {
                _Method.pick => _buildMethodPicker(context),
                _Method.browser => _buildBrowserList(context),
                _Method.paste => _buildPasteForm(context),
              },
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMethodPicker(BuildContext context) {
    return Column(
      children: [
        Text(
          '首次使用需要配置 Cookie\n请选择一种获取方式',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _MethodCard(
                icon: Icons.travel_explore,
                title: '从浏览器导入',
                subtitle: '自动读取本机浏览器中已登录的抖音 Cookie（推荐）',
                onTap: () => setState(() => _method = _Method.browser),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _MethodCard(
                icon: Icons.content_paste,
                title: '手动粘贴',
                subtitle: '从浏览器开发者工具复制 Cookie 后粘贴到应用中',
                onTap: () => setState(() => _method = _Method.paste),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrowserList(BuildContext context) {
    if (_browsers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择已登录抖音的浏览器：', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          '提示：读取 Chromium 内核浏览器的 Cookie 通常需要先关闭对应浏览器；若失败请尝试以管理员身份运行本程序。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in _browsers)
              ChoiceChip(
                label: Text(b),
                selected: _selectedBrowser == b,
                onSelected: _extracting
                    ? null
                    : (_) => _extractFromBrowser(b),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_extracting)
          const Row(
            children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('正在读取浏览器 Cookie…'),
            ],
          ),
      ],
    );
  }

  Widget _buildPasteForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('粘贴 Cookie 内容', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        const Text.rich(
          TextSpan(children: [
            TextSpan(text: '获取方式：电脑浏览器登录 '),
            TextSpan(text: 'www.douyin.com', style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: '，按 F12 打开开发者工具 → 网络(Network) → 刷新页面 → 任选请求 → 复制请求头中完整的 Cookie 值。'),
          ]),
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pasteController,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '将 Cookie 粘贴到这里…',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: _pasting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('校验并保存'),
          onPressed: _pasting ? null : _submitPaste,
        ),
      ],
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
