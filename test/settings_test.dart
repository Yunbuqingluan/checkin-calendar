import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/app_theme.dart';
import 'package:my_calendar_app/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(seed: AppColors.pink, brightness: Brightness.light),
    home: const HomePage(initialProjects: [], enableOnboarding: false),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.menu_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('设置'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('设置里有「导出位置」，默认是系统下载目录', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _openSettings(tester);

    expect(find.text('导出位置'), findsOneWidget);
    expect(find.textContaining('下载/打卡日历导出'), findsOneWidget);
  });

  testWidgets('设过自定义目录时，设置里显示那个路径', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'export_dir': r'D:\打卡备份'});

    await _openSettings(tester);

    expect(find.textContaining(r'D:\打卡备份'), findsOneWidget);
  });

  testWidgets('点导出位置的「更改」弹出选项面板', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _openSettings(tester);

    // 数据目录和导出位置各有一个「更改」，导出位置是后面那个
    await tester.tap(find.text('更改').last);
    await tester.pumpAndSettle();

    expect(find.text('选择文件夹'), findsOneWidget);
  });
}
