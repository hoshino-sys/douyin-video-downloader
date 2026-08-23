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
        throw BackendException('后端服务启动超时或异常退出\n\n${backend.logBuffer.take(8).join('\n')}');
      }
      final client = ApiClient(baseUrl: 'http://127.0.0.1:${backend.port}');
      final info = await client.bootstrap();
      App.backend = backend;
      App.client = client;
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
                        'DouK 下载器',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
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
