import 'package:flutter/material.dart';

import 'app_theme.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('今日待打卡')),
      body: pending.isEmpty && done.isEmpty
          ? const EmptyState(
              icon: Icons.wb_sunny_rounded,
              title: '今天没有需要打卡的项目',
              subtitle: '所有项目今天都不用打卡，休息一下吧',
              color: AppColors.mango,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                if (pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Pill(
                        text: '今天的项目都打了，继续保持',
                        color: AppColors.onImage(AppColors.mint, 0.55),
                        background: AppColors.mint,
                        icon: Icons.celebration_rounded,
                      ),
                    ),
                  ),
                if (pending.isNotEmpty)
                  SectionHeader(
                    title: '待打卡',
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
                    trailing: Pill(
                      text: '${pending.length} 项',
                      color: AppColors.pink,
                      dense: true,
                    ),
                  ),
                for (final p in pending) _buildRow(p, today0, pending: true),
                if (done.isNotEmpty) ...[
                  SectionHeader(
                    title: '今日已完成',
                    color: AppColors.mint,
                    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                  ),
                  for (final p in done) _buildRow(p, today0, pending: false),
                ],
              ],
            ),
    );
  }

  Widget _buildRow(Project p, DateTime today, {required bool pending}) {
    final accent = pending ? AppColors.of(p.id) : AppColors.mint;
    final streak = p.currentStreak(today);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        color: pending
            ? AppColors.tint(accent, 0.10)
            : AppColors.tint(accent, 0.08),
        borderColor: accent.withValues(alpha: 0.20),
        shadowColor: accent,
        onTap: () => _open(p),
        child: Row(
          children: [
            IconBubble(
              size: 46,
              color: Colors.white,
              child: ProjectIcon(project: p, size: 34),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_statusText(p, today)}'
                          '${p.reminderOn ? ' · 提醒 ${p.reminderTimeText}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSoft,
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            pending
                ? Icon(Icons.chevron_right_rounded, color: accent)
                : Pill(
                    text: '已完成',
                    color: AppColors.inkSoft,
                    iconColor: AppColors.mint,
                    background: Colors.white,
                    icon: Icons.check_circle_rounded,
                    dense: true,
                  ),
          ],
        ),
      ),
    );
  }
}
