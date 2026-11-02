import 'package:flutter/material.dart';

import 'models.dart';
import 'project_detail_page.dart';
import 'project_icon.dart';

/// 统计总览：把所有项目的数据横向摆在一起看。
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key, required this.projects, this.onChanged});

  final List<Project> projects;
  final VoidCallback? onChanged;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Future<void> _open(Project p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p)),
    );
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  String _dayText(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(today.year, today.month, today.day - 29);
    final scheme = Theme.of(context).colorScheme;

    final projects = widget.projects;
    final totalCheckIns =
        projects.fold<int>(0, (sum, p) => sum + p.records.length);
    final totalDays = projects.fold<int>(0, (sum, p) => sum + p.checkedDayCount);
    final pending = projects
        .where((p) => p.isRequiredOn(today) && !p.reachedLimitOn(today))
        .length;
    final rate = projects.isEmpty
        ? 0.0
        : projects
                .map((p) => p.completionRate(from, today))
                .reduce((a, b) => a + b) /
            projects.length;

    return Scaffold(
      appBar: AppBar(title: const Text('统计总览')),
      body: projects.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights, size: 56, color: scheme.outline),
                    const SizedBox(height: 16),
                    const Text('还没有项目', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      '先到首页新建一个项目，这里就会显示汇总数据',
                      style: TextStyle(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.folder_outlined,
                      label: '项目数',
                      value: '${projects.length}',
                    ),
                    const SizedBox(width: 10),
                    _StatTile(
                      icon: Icons.done_all,
                      label: '累计打卡',
                      value: '$totalCheckIns 次',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.today,
                      label: '今日待打卡',
                      value: '$pending 项',
                    ),
                    const SizedBox(width: 10),
                    _StatTile(
                      icon: Icons.percent,
                      label: '近 30 天完成率',
                      value: '${(rate * 100).round()}%',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    '各项目（累计 $totalDays 个打卡日）',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.outline,
                    ),
                  ),
                ),
                for (final p in projects)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _open(p),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProjectIcon(project: p, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '累计 ${p.records.length} 次 · '
                                        '打卡 ${p.checkedDayCount} 天 · '
                                        '连续 ${p.currentStreak(today)} 天',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${(p.completionRate(from, today) * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: p.completionRate(from, today),
                                minHeight: 6,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              p.lastCheckInTime == null
                                  ? '还没有打卡记录'
                                  : '最近打卡 ${_dayText(p.lastCheckInTime!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
