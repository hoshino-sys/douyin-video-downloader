import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models.dart';
import '../services/toast.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Timer? _timer;
  List<TaskInfo> _tasks = [];
  String? _error;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final tasks = await App.client!.tasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _error != null && _tasks.isEmpty
          ? ListView(children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('加载失败：$_error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ])
          : _tasks.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        Icon(Icons.task_outlined,
                            size: 48, color: Theme.of(context).disabledColor),
                        const SizedBox(height: 12),
                        Text('暂无任务', style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 8),
                        Text('在“链接下载”或“账号下载”中创建任务后会显示在这里',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    final expanded = _expanded.contains(task.id);
                    return _TaskCard(
                      task: task,
                      expanded: expanded,
                      onToggle: () => setState(() {
                        if (expanded) {
                          _expanded.remove(task.id);
                        } else {
                          _expanded.add(task.id);
                        }
                      }),
                    );
                  },
                ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskInfo task;
  final bool expanded;
  final VoidCallback onToggle;

  const _TaskCard({required this.task, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[task.createdAt];
    if (task.message.isNotEmpty) subtitleParts.add(task.message);
    if (!task.isRunning && task.finishedAt.isNotEmpty) {
      subtitleParts.add('完成于 ${task.finishedAt}');
    }
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            leading: switch (task.status) {
              'running' => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              'success' => const Icon(Icons.check_circle, color: Colors.green),
              _ => Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            },
            title: Text(task.label.isEmpty ? task.type : task.label),
            subtitle: Text(subtitleParts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (task.downloadDir.isNotEmpty)
                IconButton(
                  tooltip: '打开文件位置',
                  icon: const Icon(Icons.folder_open, size: 20),
                  onPressed: () async {
                    try {
                      if (Platform.isWindows) {
                        var target = task.downloadDir;
                        if (!await Directory(target).exists()) {
                          final parent = Directory(target).parent.path;
                          if (await Directory(parent).exists()) {
                            target = parent;
                          } else {
                            if (context.mounted) {
                              AppToast.show(context, '路径不存在：$target');
                            }
                            return;
                          }
                        }
                        await Process.run('explorer.exe', ['/separate,$target']);
                        if (context.mounted) AppToast.show(context, '已打开文件夹');
                      } else {
                        final ok = await App.client!.openFolder(task.downloadDir);
                        if (context.mounted) {
                          AppToast.show(context, ok ? '已打开文件夹' : '打开失败，请检查路径是否存在');
                        }
                      }
                    } catch (e) {
                      if (context.mounted) AppToast.show(context, '打开失败：$e');
                    }
                  },
                ),
              Text(
                switch (task.status) {
                  'running' => '进行中',
                  'success' => '已完成',
                  _ => '失败',
                },
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ]),
            onTap: onToggle,
          ),
          if (task.isRunning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          if (expanded) ...[
            const Divider(height: 1),
            if (task.downloadDir.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  const Icon(Icons.folder_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('保存至：${task.downloadDir}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  IconButton(
                    tooltip: '复制路径',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: task.downloadDir));
                      if (context.mounted) AppToast.show(context, '已复制路径');
                    },
                  ),
                ]),
              ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: task.logs.isEmpty
                  ? Text('暂无日志…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('实时日志',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('${task.logs.length} 条',
                                style: Theme.of(context).textTheme.labelSmall),
                            IconButton(
                              tooltip: '复制日志',
                              icon: const Icon(Icons.copy_all, size: 16),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: task.logs.join('\n')));
                                if (context.mounted) AppToast.show(context, '已复制日志');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              task.logs.join('\n'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontFamilyFallback: const ['Consolas', 'Courier'],
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
