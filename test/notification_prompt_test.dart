import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/app_theme.dart';
import 'package:my_calendar_app/home_page.dart';
import 'package:my_calendar_app/models.dart';
import 'package:my_calendar_app/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Project _project({required bool reminder}) => Project(
      id: 'p-$reminder',
      name: '晨间阅读',
      createdAt: DateTime(2026, 1, 1),
      reminderOn: reminder,
      reminderMinutes: 20 * 60,
    );

Future<void> _pump(WidgetTester tester, List<Project> projects) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(seed: AppColors.pink, brightness: Brightness.light),
    home: HomePage(initialProjects: projects, enableOnboarding: false),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.debugSupported = true;
    NotificationService.debugHasPermission = () async => false;
  });

  tearDown(() {
    NotificationService.debugSupported = null;
    NotificationService.debugHasPermission = null;
  });

  testWidgets('有提醒项目但没通知权限时，启动后提示一次', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await _pump(tester, [_project(reminder: true)]);

    expect(find.text('提醒可能收不到'), findsOneWidget);
    expect(find.textContaining('有 1 个项目开了打卡提醒'), findsOneWidget);
    expect(find.text('去开启'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);

    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(find.text('提醒可能收不到'), findsNothing);
  });

  testWidgets('已经有通知权限就不提示', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    NotificationService.debugHasPermission = () async => true;

    await _pump(tester, [_project(reminder: true)]);

    expect(find.text('提醒可能收不到'), findsNothing);
  });

  testWidgets('没有开启提醒的项目时不检查权限', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    var probed = false;
    NotificationService.debugHasPermission = () async {
      probed = true;
      return false;
    };

    await _pump(tester, [_project(reminder: false)]);

    expect(find.text('提醒可能收不到'), findsNothing);
    expect(probed, isFalse);
  });

  testWidgets('平台不支持通知时（桌面/Web）不提示', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    NotificationService.debugSupported = false;

    await _pump(tester, [_project(reminder: true)]);

    expect(find.text('提醒可能收不到'), findsNothing);
  });
}
