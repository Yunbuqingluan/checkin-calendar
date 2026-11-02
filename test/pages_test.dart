import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/models.dart';
import 'package:my_calendar_app/overview_page.dart';
import 'package:my_calendar_app/today_page.dart';

Project _project({
  required String id,
  required String name,
  int daysAgo = 6,
  int checkInDays = 0,
  int dailyLimit = 1,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final p = Project(
    id: id,
    name: name,
    createdAt: DateTime(today.year, today.month, today.day - daysAgo),
    dailyLimit: dailyLimit,
  );
  for (var i = 0; i < checkInDays; i++) {
    p.records.add(CheckInRecord(
      id: '$id-$i',
      time: DateTime(today.year, today.month, today.day - i, 9),
    ));
  }
  return p;
}

void main() {
  testWidgets('统计总览显示汇总数字和每个项目的完成率', (tester) async {
    final projects = [
      _project(id: 'a', name: '晨间阅读', daysAgo: 6, checkInDays: 4),
      _project(id: 'b', name: '夜跑', daysAgo: 6, checkInDays: 0),
    ];

    await tester.pumpWidget(
      MaterialApp(home: OverviewPage(projects: projects)),
    );
    await tester.pumpAndSettle();

    expect(find.text('统计总览'), findsOneWidget);
    expect(find.text('项目数'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('累计打卡'), findsOneWidget);
    expect(find.text('4 次'), findsOneWidget);
    expect(find.text('今日待打卡'), findsOneWidget);
    expect(find.text('近 30 天完成率'), findsOneWidget);

    expect(find.text('晨间阅读'), findsOneWidget);
    expect(find.textContaining('累计 4 次'), findsOneWidget);
    // 夜跑一天都没打卡
    expect(find.text('还没有打卡记录'), findsOneWidget);
  });

  testWidgets('统计总览在空列表时给提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OverviewPage(projects: [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有项目'), findsOneWidget);
    expect(find.textContaining('新建一个项目'), findsOneWidget);
  });

  testWidgets('今日待打卡只列今天该打且没打满的项目', (tester) async {
    final done = _project(id: 'c', name: '喝水', daysAgo: 3, checkInDays: 1);
    final pending = _project(id: 'd', name: '背单词', daysAgo: 3);
    final projects = [done, pending];

    await tester.pumpWidget(
      MaterialApp(home: TodayPage(projects: projects)),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日待打卡'), findsWidgets);
    expect(find.text('背单词'), findsOneWidget);
    expect(find.text('喝水'), findsOneWidget);
    expect(find.text('今日已完成'), findsOneWidget);
    expect(find.textContaining('还没打卡'), findsOneWidget);
  });

  testWidgets('今天没有任务时给鼓励文案', (tester) async {
    // 只建一个「每周一」的项目，今天多半不是周一
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final otherWeekday = today.weekday == 1 ? 2 : 1;
    final p = Project(
      id: 'weekly',
      name: '周会复盘',
      createdAt: today.subtract(const Duration(days: 20)),
      frequencyType: FrequencyType.weekly,
      weeklyDays: [otherWeekday],
    );

    await tester.pumpWidget(MaterialApp(home: TodayPage(projects: [p])));
    await tester.pumpAndSettle();

    expect(find.text('今天没有需要打卡的项目'), findsOneWidget);
  });
}
