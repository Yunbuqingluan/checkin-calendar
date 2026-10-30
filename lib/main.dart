import 'package:flutter/material.dart';
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
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);
  static final ValueNotifier<Color> seedColor = ValueNotifier(Colors.teal);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: seedColor,
          builder: (context, color, _) {
            return MaterialApp(
              title: '打卡日历',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: color),
                useMaterial3: true,
                cardTheme: const CardThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  elevation: 2,
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: color,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                cardTheme: const CardThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  elevation: 2,
                ),
              ),
              home: const HomePage(),
            );
          },
        );
      },
    );
  }
}
