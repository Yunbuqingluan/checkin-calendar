import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_calendar_app/main.dart';

/// 把「应用文档目录」指到临时目录，避免测试碰真实用户数据
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory tempDir;

  setUp(() {
    // 注意：testWidgets 跑在 fake-async 区里，异步 IO 会永远挂起，
    // 所以这里只能同步建目录
    tempDir = Directory.systemTemp.createTempSync('calendar_app_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows 上临时文件偶尔还被占用，删不掉不影响测试结论
    }
  });

  /// 让真实文件 IO 跑完：fake-async 区里必须借 runAsync 让出时间
  Future<void> flushIo(WidgetTester tester, {int rounds = 4}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// 等首页读完本地数据。
  /// 加载用到了真实文件 IO，而 testWidgets 默认在 fake-async 区里跑，
  /// 所以要在 runAsync 里让出真实时间，再手动 pump 几帧。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    while (tester.binding.hasScheduledFrame) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await flushIo(tester);
  }

  testWidgets('没有项目时显示引导文案', (tester) async {
    await tester.pumpWidget(const MyApp());
    await settle(tester);

    expect(find.text('还没有项目，点右上角 + 新建'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
  });

  testWidgets('新建项目后首页出现卡片，并写入本地文件', (tester) async {
    await tester.pumpWidget(const MyApp());
    await settle(tester);

    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '晨间阅读');
    await tester.tap(find.text('创建'));
    await settle(tester);

    // 卡片标题是描边文字，会渲染成两个 Text
    expect(find.text('晨间阅读'), findsWidgets);
    expect(find.text('还没有项目，点右上角 + 新建'), findsNothing);

    final saved = File('${tempDir.path}/checkin_app/projects.json');
    // 落盘是真实 IO，等它真正写完（测试里只能靠 runAsync 让出真实时间）
    for (var i = 0; i < 20 && !saved.existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsStringSync(), contains('晨间阅读'));
  });

  testWidgets('搜索能过滤项目', (tester) async {
    await tester.pumpWidget(const MyApp());
    await settle(tester);

    for (final name in ['晨间阅读', '夜跑']) {
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建项目'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, name);
      await tester.tap(find.text('创建'));
      await settle(tester);
    }

    expect(find.text('夜跑'), findsWidgets);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '晨间');
    await tester.pumpAndSettle();

    expect(find.text('晨间阅读'), findsWidgets);
    expect(find.text('夜跑'), findsNothing);
  });
}
