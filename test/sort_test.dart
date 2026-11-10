import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/app_theme.dart';
import 'package:my_calendar_app/home_page.dart';
import 'package:my_calendar_app/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Project _p(String name) => Project(
      id: name,
      name: name,
      createdAt: DateTime.now(),
    );

Future<void> _enterSorting(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(seed: AppColors.pink, brightness: Brightness.light),
    home: HomePage(
      initialProjects: [_p('AAA'), _p('BBB'), _p('CCC')],
      enableOnboarding: false,
    ),
  ));
  await tester.pumpAndSettle();

  await tester.longPress(find.text('AAA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('拖拽排序'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('排序模式下按住卡片就能拖动改顺序', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _enterSorting(tester);

    final before = tester.getCenter(find.text('AAA')).dy;

    // 不用等长按，按下直接拖
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('AAA')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final after = tester.getCenter(find.text('AAA')).dy;
    expect(after, greaterThan(before + 60),
        reason: '拖动后第一张卡应该往下走，说明拖拽手势没被卡片自己的手势吃掉');
  });

  testWidgets('排序模式卡片右侧有抓手提示', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _enterSorting(tester);

    expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));
  });

  testWidgets('非排序模式下长按卡片仍然弹出操作面板', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(seed: AppColors.pink, brightness: Brightness.light),
      home: HomePage(
        initialProjects: [_p('AAA')],
        enableOnboarding: false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('AAA'));
    await tester.pumpAndSettle();

    expect(find.text('编辑项目'), findsOneWidget);
    expect(find.text('拖拽排序'), findsOneWidget);
    expect(find.text('删除项目'), findsOneWidget);
  });
}
