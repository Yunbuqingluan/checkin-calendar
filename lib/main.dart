import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 提前初始化通知插件，首帧之后就能拿到权限状态
  await NotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  /// 只保留深色 / 浅色 / 跟随系统三种外观
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: '打卡日历',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildAppTheme(seed: AppColors.pink, brightness: Brightness.light),
          darkTheme:
              buildAppTheme(seed: AppColors.pink, brightness: Brightness.dark),
          home: const HomePage(),
        );
      },
    );
  }
}
