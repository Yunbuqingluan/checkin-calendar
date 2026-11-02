import 'package:flutter/material.dart';

import 'models.dart';
import 'project_detail_page.dart';
import 'project_icon.dart';

/// 今日待打卡：把「今天该打但还没打满」的项目单独列出来，省得在首页一个个找。
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.projects, this.onChanged});

  final List<Project> projects;

  /// 从详情页回来、数据可能变了，通知首页刷新
  final VoidCallback? onChanged;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Future<void> _open(Project p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p)),
    );
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  String _statusText(Project p, DateTime today) {
    final done = p.recordsOn(today).length;
    if (p.dailyLimit == -1) {
      return done == 0 ? '还没打卡' : '今天已经打了 $done 次';
    }
    return done == 0 ? '还没打卡' : '今天已打 $done/${p.dailyLimit} 次';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final pending = widget.projects
        .where((p) => p.isRequiredOn(today0) && !p.reachedLimitOn(today0))
        .toList();
    final done = widget.projects
        .where((p) => p.isRequiredOn(today0) && p.reachedLimitOn(today0))
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('今日待打卡')),
      body: pending.isEmpty && done.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wb_sunny_outlined,
                        size: 56, color: scheme.outline),
                    const SizedBox(height: 16),
                    const Text(
                      '今天没有需要打卡的项目',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '所有项目今天都不用打卡，休息一下吧',
                      style: TextStyle(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '今天的项目都打了，继续保持 🎉',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
                for (final p in pending)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      leading: ProjectIcon(project: p),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${_statusText(p, today0)}'
                        '${p.reminderOn ? ' · 提醒 ${p.reminderTimeText}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(p),
                    ),
                  ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '今日已完成',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.outline,
                      ),
                    ),
                  ),
                  for (final p in done)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        leading: ProjectIcon(project: p),
                        title: Text(p.name),
                        subtitle: Text(
                          _statusText(p, today0),
                          style: const TextStyle(color: Colors.green),
                        ),
                        trailing: const Icon(Icons.check_circle,
                            color: Colors.green),
                        onTap: () => _open(p),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
