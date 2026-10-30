import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/models.dart';
import 'package:my_calendar_app/project_detail_page.dart';

Project _project() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final p = Project(
    id: 'detail-test',
    name: '晨间阅读',
    createdAt: today.subtract(const Duration(days: 10)),
    metrics: [Metric(id: 'm-pages', name: '页数', unit: '页')],
  );
  p.records.add(CheckInRecord(
    id: 'r1',
    time: today.add(const Duration(hours: 7, minutes: 30)),
    note: '读了两章',
    metricValues: const {'m-pages': 42},
  ));
  return p;
}

Widget _wrap(Project p) => MaterialApp(home: ProjectDetailPage(project: p));

void main() {
  testWidgets('详情页显示当月日历、星期表头与底部按钮', (tester) async {
    final p = _project();
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    for (final w in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.text(w), findsWidgets);
    }
    // 今天已经打过卡，所以底部是「统计 + 补打卡」两个按钮
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('补打卡'), findsOneWidget);
  });

  testWidgets('选中当天能看到打卡记录内容', (tester) async {
    final p = _project();
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text('${now.year}年${now.month}月${now.day}日'), findsOneWidget);
    expect(find.text('读了两章'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.textContaining('页数 42.0页'), findsOneWidget);
  });

  testWidgets('点「补打卡」会打开选日期对话框', (tester) async {
    final p = _project();
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    await tester.tap(find.text('补打卡'));
    await tester.pumpAndSettle();

    // 主页面和对话框各有一个月份标题、各有一个左箭头
    expect(find.text('${now.year}年${now.month}月'), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_left), findsNWidgets(2));

    // 对话框里翻到上个月
    await tester.tap(find.byIcon(Icons.chevron_left).last);
    await tester.pumpAndSettle();
    final prev = DateTime(now.year, now.month - 1);
    expect(find.text('${prev.year}年${prev.month}月'), findsOneWidget);
  });

  testWidgets('打卡按钮在未打卡的项目上会出现', (tester) async {
    final now = DateTime.now();
    final p = Project(
      id: 'fresh',
      name: '夜跑',
      createdAt: DateTime(now.year, now.month, now.day),
    );
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    expect(find.text('打卡'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);

    await tester.tap(find.text('打卡'));
    await tester.pumpAndSettle();
    expect(find.text('备注（可选）'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // 凌晨 0:00~0:30 打卡会多问一句「算今天还是前一天」
    if (find.text('算作今天').evaluate().isNotEmpty) {
      await tester.tap(find.text('算作今天'));
      await tester.pumpAndSettle();
    }

    expect(p.records, hasLength(1));
  });
}
