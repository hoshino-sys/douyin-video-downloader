import 'package:flutter/material.dart';

import '../app.dart';
import '../services/api_client.dart';
import '../services/backend_process.dart';
import 'home_shell.dart';
import 'onboarding_page.dart';

class SplashPage extends StatefulWidget {
  final bool autoStart;

  const SplashPage({super.key, this.autoStart = true});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _statusText = '正在启动后端服务…';
  String? _error;
  String? _logTail;
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoStart) _bootstrap();
    });
  }

  Future<void> _bootstrap({bool retry = false}) async {
    if (retry) {
      App.reset();
      setState(() {
        _error = null;
        _statusText = '正在重新启动后端服务…';
      });
    }
    try {
      final backend = BackendProcess();
      await backend.start();
      setState(() => _statusText = '正在等待后端就绪…（首次启动可能较慢）');
      final healthy = await backend.waitHealthy();
      if (!healthy) {
        final logs = backend.logBuffer;
        final tail = logs.length > 40 ? logs.sublist(logs.length - 40) : logs;
        throw BackendException(
          '后端服务启动超时或异常退出。常见原因（按概率排序）：\n'
          '1) 杀毒软件（360/Defender 等）隔离了 backend 目录内的文件：'
          '请恢复被隔离文件，或将本程序目录加入杀软白名单后重新解压；\n'
          '2) 压缩包解压不完整或经 QQ/微信中转损坏：请重新获取并完整解压；\n'
          '3) 程序路径含中文/特殊字符且系统非中文区域：'
          '把整个文件夹移动到纯英文路径（如 D:\\yx_dl）后再试。\n'
          '—— 以下为后端日志（末尾行）——\n${tail.join('\n')}',
        );
      }
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${backend.port}');
      final info = await client.bootstrap();
      App.backend = backend;
      App.client = client;
      if (!mounted) return;
      setState(() => _version = info.version);
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => (info.disclaimerAccepted && info.cookieConfigured)
            ? HomeShell(cookieLoggedIn: info.cookieLoggedIn)
            : OnboardingPage(info: info),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        if (e is BackendException && e.message.contains('\n')) {
          _logTail = e.toString();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_rounded,
                          size: 72, color: Color(0xFFFE2C55)),
                      const SizedBox(height: 24),
                      Text(
                        '夜星视频下载器',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_version.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'v$_version',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline),
                        ),
                      ],
                      const SizedBox(height: 32),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_statusText,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.error_outline,
                          size: 56, color: Theme.of(context).colorScheme.error),
                      const SizedBox(height: 16),
                      Text('后端服务启动失败',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              _logTail ?? _error!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                        onPressed: () => _bootstrap(retry: true),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
