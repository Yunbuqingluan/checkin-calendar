import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// 打卡提醒：把每个项目「下一次该打卡的时刻」注册成系统通知。
///
/// 设计取舍：
/// - 一次只排未来 [daysAhead] 天的一次性通知，而不是每天重复通知。
///   频率规则（隔天 / 周几 / 每月几号）没法用系统的重复通知表达，
///   而提前排好具体日期，就能精确跳过节假日的空档。
/// - 每次数据变更（打卡、编辑、删除）都会整体重排一次，
///   已经打完卡的那天会被自动跳过，不会误报。
/// - 用 inexactAllowWhileIdle 而不是精确闹钟：省电，也不需要用户单独授权
///   精确闹钟权限（Android 12+ 的 SCHEDULE_EXACT_ALARM）；提醒误差几分钟可以接受。
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'checkin_reminder';
  static const String _channelName = '打卡提醒';
  static const String _channelDesc = '到了设定的时间提醒你去打卡';
  static const String _icon = 'ic_notification';
  static const int daysAhead = 30;

  static bool _ready = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 测试用：绕开平台判断
  @visibleForTesting
  static bool? debugSupported;

  /// 测试用：直接给出「有没有通知权限」
  @visibleForTesting
  static Future<bool> Function()? debugHasPermission;

  /// 这个平台能不能发通知（桌面和 Web 上直接跳过相关检查）
  static bool get supported => debugSupported ?? _supported;

  /// 初始化插件与时区数据，重复调用是安全的。
  static Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      const android = AndroidInitializationSettings(_icon);
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
      );

      tz_data.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      try {
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        // 时区名拿不到就用设备默认时区，通知时间会略有偏差但不影响功能
      }

      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _channelId,
                _channelName,
                description: _channelDesc,
                importance: Importance.high,
              ),
            );
      }
      _ready = true;
    } catch (e) {
      debugPrint('通知初始化失败：$e');
    }
  }

  /// 申请通知权限（Android 13+ / iOS），返回是否拿到权限。
  static Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final impl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.requestNotificationsPermission() ?? false;
      }
      final impl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await impl?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } catch (e) {
      debugPrint('申请通知权限失败：$e');
      return false;
    }
  }

  /// 当前是否已有通知权限。
  static Future<bool> hasPermission() async {
    final probe = debugHasPermission;
    if (probe != null) return probe();
    if (!supported) return false;
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final impl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await impl?.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统的通知设置页，方便用户手动放行。
  static Future<void> openSettings() async {
    if (!_supported) return;
    await init();
    try {
      await _plugin.openAppNotificationSettings();
    } catch (e) {
      debugPrint('打开通知设置失败：$e');
    }
  }

  /// 按当前项目列表整体重排提醒。任何数据变更后调用即可。
  static Future<void> syncAll(List<Project> projects) async {
    if (!_supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final now = DateTime.now();
      for (final project in projects) {
        if (!project.reminderOn) continue;
        for (final at in project.upcomingReminderTimes(now, days: daysAhead)) {
          await _plugin.zonedSchedule(
            id: _notificationId(project.id, at),
            title: '${project.name} · 该打卡了',
            body: '现在是 ${project.reminderTimeText}，完成今天的记录吧',
            scheduledDate: tz.TZDateTime.from(at, tz.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                _channelName,
                channelDescription: _channelDesc,
                icon: _icon,
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: project.id,
          );
        }
      }
    } catch (e) {
      debugPrint('重排提醒失败：$e');
    }
  }

  /// 取消所有待发的提醒（关掉提醒开关或清空项目时用）。
  static Future<void> cancelAll() async {
    if (!_supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('取消提醒失败：$e');
    }
  }

  /// 同一个项目同一天始终得到同一个 id，重排时不会互相覆盖别的项目。
  static int _notificationId(String projectId, DateTime at) =>
      Object.hash(projectId, at.year, at.month, at.day) & 0x7FFFFFFF;
}
