import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/coach_guide.dart';
import 'package:my_calendar_app/home_page.dart';
import 'package:my_calendar_app/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => '$root/Downloads';
}

/// 引导层里有循环的呼吸动画，不能用 pumpAndSettle
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Project _project() => Project(
      id: 'p1',
      name: '晨间阅读',
      iconPath: 'reading.webp',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    );

void main() {
  testWidgets('首次打开在主界面用箭头一步步指引，走完记住状态', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: HomePage(initialProjects: [])),
    );
    await _settle(tester);

    // 第一步指向右上角「+」
    expect(find.byType(CoachGuide), findsOneWidget);
    expect(find.textContaining('点这里新建一个项目'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await _settle(tester);
    expect(find.textContaining('项目多了用搜索'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await _settle(tester);
    expect(find.textContaining('左边的菜单'), findsOneWidget);
    expect(find.text('开始使用'), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await _settle(tester);

    expect(find.byType(CoachGuide), findsNothing);
    expect(await OnboardingFlag.shouldShow(), isFalse);
  });

  testWidgets('看过之后不再出现', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done_v1': true});

    await tester.pumpWidget(
      const MaterialApp(home: HomePage(initialProjects: [])),
    );
    await _settle(tester);

    expect(find.byType(CoachGuide), findsNothing);
    expect(find.textContaining('点这里新建一个项目'), findsNothing);
  });

  testWidgets('点「跳过」直接结束并记住', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: HomePage(initialProjects: [])),
    );
    await _settle(tester);
    expect(find.byType(CoachGuide), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await _settle(tester);

    expect(find.byType(CoachGuide), findsNothing);
    expect(await OnboardingFlag.shouldShow(), isFalse);
  });

  testWidgets('已有项目时多一步指向项目卡片', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProjects: [_project()])),
    );
    await _settle(tester);

    expect(find.text('1/4'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('下一步'));
      await _settle(tester);
    }

    expect(find.textContaining('点卡片进入详情'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await _settle(tester);
    expect(find.byType(CoachGuide), findsNothing);
  });

  testWidgets('设置里「重新查看新手引导」能再看一次', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done_v1': true});
    final tempDir = Directory.systemTemp.createTempSync('coach_guide_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows 上偶发占用
      }
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomePage(initialProjects: [])),
    );
    await _settle(tester);
    expect(find.byType(CoachGuide), findsNothing);

    // 打开侧边栏 → 设置 → 重新查看新手引导
    await tester.tap(find.byIcon(Icons.menu));
    await _settle(tester);
    await tester.tap(find.text('设置'));
    await _settle(tester);

    final guideEntry = find.text('重新查看新手引导');
    expect(guideEntry, findsOneWidget);

    // 弹窗内容可滚动，先滚到按钮可见再点
    await tester.ensureVisible(guideEntry);
    await _settle(tester);
    await tester.tap(guideEntry);
    await _settle(tester);

    expect(find.byType(CoachGuide), findsOneWidget);
  });
}
