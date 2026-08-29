import 'dart:async';
import 'dart:convert';
import 'dart:io';

class BackendException implements Exception {
  final String message;
  BackendException(this.message);

  @override
  String toString() => message;
}

class BackendProcess {
  Process? _process;
  int _port = 0;
  final List<String> logBuffer = [];
  bool _exited = false;

  int get port => _port;

  Future<void> start() async {
    final appRoot = File(Platform.resolvedExecutable).parent.path;
    final exe = _findBackendExe();
    if (exe != null) {
      _port = await _pickFreePort();
      try {
        _process = await Process.start(
          exe.path,
          ['--host', '127.0.0.1', '--port', '$_port'],
          workingDirectory: exe.parent.path,
          environment: {'DOUK_HOME': appRoot},
        );
      } catch (e) {
        throw BackendException('启动后端进程失败：$e');
      }
    } else {
      final script = _findBackendScript();
      if (script == null) {
        throw BackendException(
            '未找到 gui/backend.py 或 backend.exe，请确认应用位于项目目录内，或设置环境变量 DOUK_BACKEND 指向该文件');
      }
      final python = await _findPython(script.parent.parent);
      if (python == null) {
        throw BackendException('未找到可用的 Python (>=3.12) 环境，请安装 Python 3.12 并执行 pip install -r requirements.txt，或使用自带 backend.exe 的发布版');
      }
      _port = await _pickFreePort();
      try {
        _process = await Process.start(
          python,
          [script.path, '--host', '127.0.0.1', '--port', '$_port'],
          workingDirectory: script.parent.parent.path,
        );
      } catch (e) {
        throw BackendException('启动后端进程失败：$e');
      }
    }
    _process!.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen(logBuffer.add);
    _process!.stderr
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      logBuffer.add(line);
      if (logBuffer.length > 200) logBuffer.removeAt(0);
    });
    unawaited(_process!.exitCode.then((code) {
      _exited = true;
      logBuffer.add('[进程已退出，代码 $code]');
    }));
  }

  Future<bool> waitHealthy({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_exited) return false;
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:$_port/api/gui/health'))
              .timeout(const Duration(seconds: 3));
          final response = await request.close();
          if (response.statusCode == 200) {
            await response.drain<void>();
            return true;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void kill() {
    _process?.kill();
    _process = null;
  }

  File? _findBackendExe() {
    const exeNames = ['夜星视频下载器后端.exe', 'backend.exe', 'backend'];
    for (final start in [
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      // ignore: unnecessary_cast
      final dir = start is File ? start : start as Directory;
      // onedir 布局优先（backend/<后端exe>，启动快且稳定）
      for (final name in exeNames) {
        final onedir =
            File('${dir.path}${Platform.pathSeparator}backend${Platform.pathSeparator}$name');
        if (onedir.existsSync()) return onedir;
      }
      for (final name in exeNames) {
        final f = File('${dir.path}${Platform.pathSeparator}$name');
        if (f.existsSync()) return f;
      }
      // also check gui/<后端exe> relative to walk-up
      var walk = dir;
      for (var i = 0; i < 4; i++) {
        for (final name in exeNames) {
          final c = File(
              '${walk.path}${Platform.pathSeparator}gui${Platform.pathSeparator}$name');
          if (c.existsSync()) return c;
        }
        final parent = walk.parent;
        if (parent.path == walk.path) break;
        walk = parent;
      }
    }
    return null;
  }

  File? _findBackendScript() {
    final envPath = Platform.environment['DOUK_BACKEND'];
    if (envPath != null && File(envPath).existsSync()) {
      return File(envPath);
    }
    for (final start in [
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      var dir = start is File ? start.parent : start;
      for (var i = 0; i < 8; i++) {
        final candidate = dir.uri.resolve('gui/backend.py');
        final file = File.fromUri(candidate);
        if (file.existsSync()) return file;
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  Future<String?> _findPython(Directory projectRoot) async {
    final candidates = <String>[
      projectRoot.uri.resolve('.venv/Scripts/python.exe').toFilePath(),
      projectRoot.uri.resolve('.venv/bin/python').toFilePath(),
      'python',
      'python3',
    ];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          ['--version'],
          runInShell: true,
        ).timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  Future<int> _pickFreePort() async {
    ServerSocket? socket;
    var port = 0;
    for (var attempt = 0; attempt < 10 && port == 0; attempt++) {
      try {
        socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        port = socket.port;
      } catch (_) {
        continue;
      }
    }
    socket?.close();
    if (port == 0) throw BackendException('无法分配本地端口');
    return port;
  }
}
