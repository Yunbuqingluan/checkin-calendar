import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/models.dart';

Project _project({
  FrequencyType freq = FrequencyType.daily,
  int intervalDays = 1,
  List<int> weeklyDays = const [],
  List<int> monthlyDays = const [],
  int dailyLimit = 1,
  DateTime? createdAt,
  bool reminderOn = false,
  int reminderMinutes = 20 * 60,
}) =>
    Project(
      id: 'p1',
      name: '阅读',
      createdAt: createdAt ?? DateTime(2026, 3, 1),
      frequencyType: freq,
      intervalDays: intervalDays,
      weeklyDays: weeklyDays,
      monthlyDays: monthlyDays,
      dailyLimit: dailyLimit,
      reminderOn: reminderOn,
      reminderMinutes: reminderMinutes,
    );

CheckInRecord _record(DateTime time, {bool isMakeUp = false}) => CheckInRecord(
      id: time.microsecondsSinceEpoch.toString(),
      time: time,
      isMakeUp: isMakeUp,
    );

void main() {
  group('打卡频率规则', () {
    test('每日：创建之后每天都需要打卡', () {
      final p = _project();
      expect(p.isRequiredOn(DateTime(2026, 3, 1)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 6, 20)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 2, 28)), isFalse);
    });

    test('每隔 N 天：按创建日算起的间隔', () {
      final p = _project(freq: FrequencyType.interval, intervalDays: 2);
      expect(p.isRequiredOn(DateTime(2026, 3, 1)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 3, 2)), isFalse);
      expect(p.isRequiredOn(DateTime(2026, 3, 3)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 3, 5)), isTrue);
    });

    test('间隔填 0 时按 1 天处理，不会除零崩溃', () {
      final p = _project(freq: FrequencyType.interval, intervalDays: 0);
      expect(() => p.isRequiredOn(DateTime(2026, 3, 5)), returnsNormally);
      expect(p.isRequiredOn(DateTime(2026, 3, 5)), isTrue);
    });

    test('每周：只在选中的星期几需要打卡', () {
      final p = _project(freq: FrequencyType.weekly, weeklyDays: [1, 3]);
      expect(p.isRequiredOn(DateTime(2026, 3, 2)), isTrue); // 周一
      expect(p.isRequiredOn(DateTime(2026, 3, 3)), isFalse); // 周二
      expect(p.isRequiredOn(DateTime(2026, 3, 4)), isTrue); // 周三
    });

    test('每月：只在选中的日期需要打卡', () {
      final p = _project(freq: FrequencyType.monthly, monthlyDays: [1, 15]);
      expect(p.isRequiredOn(DateTime(2026, 3, 1)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 3, 15)), isTrue);
      expect(p.isRequiredOn(DateTime(2026, 3, 16)), isFalse);
    });
  });

  group('打卡记录', () {
    test('按天取记录、判断是否已打卡', () {
      final p = _project();
      final day = DateTime(2026, 3, 5);
      expect(p.isCheckedOn(day), isFalse);

      p.records.add(_record(DateTime(2026, 3, 5, 8, 30)));
      expect(p.isCheckedOn(day), isTrue);
      expect(p.recordsOn(day), hasLength(1));
      expect(p.recordsOn(DateTime(2026, 3, 6)), isEmpty);
    });

    test('次数上限：默认 1 次，-1 表示无上限', () {
      final p = _project(dailyLimit: 2);
      final day = DateTime(2026, 3, 5);
      p.records.add(_record(DateTime(2026, 3, 5, 8)));
      expect(p.reachedLimitOn(day), isFalse);
      p.records.add(_record(DateTime(2026, 3, 5, 20)));
      expect(p.reachedLimitOn(day), isTrue);

      final unlimited = _project(dailyLimit: -1);
      for (var i = 0; i < 5; i++) {
        unlimited.records.add(_record(DateTime(2026, 3, 5, 8 + i)));
      }
      expect(unlimited.reachedLimitOn(day), isFalse);
    });

    test('全部是补打卡时，当天标记为补打卡', () {
      final p = _project();
      final day = DateTime(2026, 3, 5);
      p.records.add(_record(DateTime(2026, 3, 5, 9), isMakeUp: true));
      expect(p.isMakeUpOn(day), isTrue);

      p.records.add(_record(DateTime(2026, 3, 5, 21)));
      expect(p.isMakeUpOn(day), isFalse);
    });

    test('指标取点按时间排序，并按截止时间过滤', () {
      final p = _project()
        ..metrics.add(Metric(id: 'm1', name: '页数', unit: '页'));
      p.records.add(_record(DateTime(2026, 3, 7))
        ..metricValues = {'m1': 40});
      p.records.add(_record(DateTime(2026, 3, 3))
        ..metricValues = {'m1': 20});
      p.records.add(_record(DateTime(2026, 3, 5))); // 没有指标值

      final points = p.metricPoints('m1', null);
      expect(points.map((e) => e.value), [20, 40]);
      expect(p.metricPoints('m1', DateTime(2026, 3, 6)), hasLength(1));
      expect(p.findMetric('m1')?.name, '页数');
      expect(p.findMetric('nope'), isNull);
    });
  });

  group('提醒排期', () {
    test('关闭提醒时没有任何提醒时刻', () {
      final p = _project();
      expect(p.upcomingReminderTimes(DateTime(2026, 3, 1, 8)), isEmpty);
    });

    test('只排需要打卡且尚未打卡的日子', () {
      final p = _project(
        freq: FrequencyType.weekly,
        weeklyDays: [1],
        reminderOn: true,
        reminderMinutes: 20 * 60,
      );
      // 2026-03-02 是周一，3-09 也是周一
      p.records.add(_record(DateTime(2026, 3, 2, 21)));

      final times = p.upcomingReminderTimes(DateTime(2026, 3, 1, 8), days: 14);
      expect(times, [DateTime(2026, 3, 9, 20)]);
    });

    test('当天提醒时刻已过就不再补排', () {
      final p = _project(reminderOn: true, reminderMinutes: 20 * 60);
      final afterReminder = DateTime(2026, 3, 1, 21);
      final times = p.upcomingReminderTimes(afterReminder, days: 2);
      expect(times.first, DateTime(2026, 3, 2, 20));
    });

    test('提醒时刻文本按 24 小时补零', () {
      expect(_project(reminderMinutes: 7 * 60 + 5).reminderTimeText, '07:05');
      expect(_project(reminderMinutes: 23 * 60 + 59).reminderTimeText, '23:59');
    });
  });

  group('序列化', () {
    test('reminderMinutes 能往返保存', () {
      final p = _project(reminderOn: true, reminderMinutes: 6 * 60 + 45);
      final restored = Project.fromJson(p.toJson());
      expect(restored.reminderOn, isTrue);
      expect(restored.reminderMinutes, 6 * 60 + 45);
      expect(restored.reminderTimeText, '06:45');
    });

    test('老数据没有 reminderMinutes 字段时默认 20:00', () {
      final json = _project().toJson()..remove('reminderMinutes');
      expect(Project.fromJson(json).reminderMinutes, 20 * 60);
    });

    test('异常的 reminderMinutes 回落到默认值', () {
      final json = _project().toJson()
        ..['reminderMinutes'] = 99999;
      expect(Project.fromJson(json).reminderMinutes, 20 * 60);
    });
  });
}
