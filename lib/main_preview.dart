import 'package:flutter/material.dart';

import 'home_page.dart';
import 'models.dart';
import 'project_detail_page.dart';

/// 只用于 Web / 桌面预览截图：用内存里的示例数据渲染页面，
/// 不读本地文件，也不参与正式打包（APK 入口是 main.dart）。
///
/// 用法：`?page=detail` 看项目详情（日历），`?page=empty` 看空状态。
void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final projects = demoProjects();
    final page = Uri.base.queryParameters['page'];
    final Widget home;
    if (page == 'detail') {
      home = ProjectDetailPage(project: projects.first);
    } else if (page == 'empty') {
      home = const HomePage(initialProjects: []);
    } else {
      home = HomePage(initialProjects: projects);
    }

    return MaterialApp(
      title: '打卡日历 · 预览',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          elevation: 2,
        ),
      ),
      home: home,
    );
  }
}

List<Project> demoProjects() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  CheckInRecord rec(DateTime time,
          {double? value, String metricId = 'm-pages', bool makeUp = false}) =>
      CheckInRecord(
        id: time.microsecondsSinceEpoch.toString(),
        time: time,
        note: '',
        metricValues: value == null ? {} : {metricId: value},
        isMakeUp: makeUp,
      );

  final reading = Project(
    id: 'demo-reading',
    name: '晨间阅读',
    iconPath: 'reading.webp',
    createdAt: today.subtract(const Duration(days: 40)),
    frequencyType: FrequencyType.daily,
    reminderOn: true,
    reminderMinutes: 20 * 60,
    metrics: [Metric(id: 'm-pages', name: '页数', unit: '页')],
  );
  for (var i = 12; i >= 0; i--) {
    if (i == 3) continue; // 留一天漏卡，日历上能看到红色
    reading.records.add(rec(
      today.subtract(Duration(days: i)).add(const Duration(hours: 7, minutes: 20)),
      value: (28 + i).toDouble(),
    ));
  }

  final running = Project(
    id: 'demo-running',
    name: '夜跑',
    iconPath: 'running.webp',
    createdAt: today.subtract(const Duration(days: 20)),
    frequencyType: FrequencyType.interval,
    intervalDays: 2,
    metrics: [Metric(id: 'm-km', name: '距离', unit: 'km')],
  );
  running.records.add(rec(
    today.subtract(const Duration(days: 1)).add(const Duration(hours: 21)),
    value: 5.2,
    metricId: 'm-km',
  ));

  final water = Project(
    id: 'demo-water',
    name: '喝水',
    iconPath: 'water.webp',
    createdAt: today.subtract(const Duration(days: 30)),
    frequencyType: FrequencyType.daily,
    dailyLimit: 8,
    metrics: [Metric(id: 'm-cup', name: '杯数', unit: '杯')],
  );
  for (var i = 0; i < 5; i++) {
    water.records.add(rec(
      today.add(Duration(hours: 8 + i * 2)),
      value: (i + 1).toDouble(),
      metricId: 'm-cup',
    ));
  }

  return [reading, running, water];
}
