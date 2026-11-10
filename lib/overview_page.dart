import 'package:flutter/material.dart';

import 'app_theme.dart';
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
          ? const EmptyState(
              icon: Icons.insights_rounded,
              title: '还没有项目',
              subtitle: '先到首页新建一个项目，这里就会显示汇总数据',
              color: AppColors.mint,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.folder_rounded,
                      label: '项目数',
                      value: '${projects.length}',
                      color: AppColors.sky,
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      icon: Icons.done_all_rounded,
                      label: '累计打卡',
                      value: '$totalCheckIns 次',
                      color: AppColors.mint,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.today_rounded,
                      label: '今日待打卡',
                      value: '$pending 项',
                      color: AppColors.mango,
                    ),
                    const SizedBox(width: 12),
                    _StatTile(
                      icon: Icons.percent_rounded,
                      label: '近 30 天完成率',
                      value: '${(rate * 100).round()}%',
                      color: AppColors.grape,
                    ),
                  ],
                ),
                SectionHeader(
                  title: '各项目',
                  padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
                  trailing: Pill(
                    text: '$totalDays 个打卡日',
                    color: AppColors.inkSoft,
                    dense: true,
                  ),
                ),
                for (final p in projects) _buildProjectCard(p, from, today),
              ],
            ),
    );
  }

  Widget _buildProjectCard(Project p, DateTime from, DateTime today) {
    final accent = AppColors.of(p.id);
    final rate = p.completionRate(from, today);
    final streak = p.currentStreak(today);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        color: AppColors.tint(accent, 0.10),
        borderColor: accent.withValues(alpha: 0.20),
        shadowColor: accent,
        onTap: () => _open(p),
        child: Row(
          children: [
            IconBubble(
              size: 50,
              color: Colors.white,
              child: ProjectIcon(project: p, size: 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (streak > 1) ...[
                        const SizedBox(width: 6),
                        Pill(
                          text: '$streak 天',
                          color: AppColors.onImage(AppColors.mango, 0.55),
                          background: AppColors.mango,
                          icon: Icons.local_fire_department_rounded,
                          dense: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '累计 ${p.records.length} 次 · 打卡 ${p.checkedDayCount} 天',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: rate,
                      minHeight: 6,
                      backgroundColor: accent.withValues(alpha: 0.16),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.lastCheckInTime == null
                        ? '还没有打卡记录'
                        : '最近打卡 ${_dayText(p.lastCheckInTime!)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MiniRing(
              value: rate,
              size: 46,
              stroke: 5,
              color: accent,
              child: Text(
                '${(rate * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        color: AppColors.tint(color, 0.14),
        borderColor: color.withValues(alpha: 0.22),
        shadowColor: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
