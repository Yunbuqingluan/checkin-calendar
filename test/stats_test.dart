import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/models.dart';

void main() {
  // 固定「今天」，避免测试结果随运行日期变化（2026-05-20 是周三）
  final today = DateTime(2026, 5, 20);

  Project daily({int createdDaysAgo = 5, int limit = 1}) => Project(
        id: 'p',
        name: '项目',
        createdAt:
            DateTime(today.year, today.month, today.day - createdDaysAgo),
        dailyLimit: limit,
      );

  void add(Project p, int month, int day, [int hour = 9]) => p.records.add(
        CheckInRecord(
          id: '$month-$day-$hour',
          time: DateTime(2026, month, day, hour),
        ),
      );

  test('checkedDayCount：同一天多次只算一天', () {
    final p = daily();
    add(p, 5, 20, 8);
    add(p, 5, 20, 19);
    add(p, 5, 19);
    expect(p.checkedDayCount, 2);
    expect(p.records.length, 3);
  });

  test('lastCheckInTime 取最晚的一条，没有记录时为 null', () {
    final p = daily();
    expect(p.lastCheckInTime, isNull);
    add(p, 5, 18);
    add(p, 5, 20, 21);
    add(p, 5, 19);
    expect(p.lastCheckInTime, DateTime(2026, 5, 20, 21));
  });

  test('currentStreak：连续打卡天数，中间漏一天就中断', () {
    final p = daily(createdDaysAgo: 5);
    add(p, 5, 20);
    add(p, 5, 19);
    add(p, 5, 18);
    // 5/17 漏了
    add(p, 5, 16);
    expect(p.currentStreak(today), 3);
  });

  test('currentStreak：今天还没打卡时不算断，从昨天起算', () {
    final p = daily(createdDaysAgo: 3);
    add(p, 5, 19);
    add(p, 5, 18);
    expect(p.currentStreak(today), 2);
  });

  test('currentStreak：今天和昨天都没打，连续天数归零', () {
    final p = daily(createdDaysAgo: 5);
    add(p, 5, 18);
    add(p, 5, 17);
    expect(p.currentStreak(today), 0);
  });

  test('completionRate：分母是应有天数，不是总天数', () {
    // 5/11 建的项目，到 5/20 一共 10 天，隔天打卡 = 5 天
    final p = daily(createdDaysAgo: 9);
    for (var d = 11; d <= 20; d += 2) {
      add(p, 5, d);
    }
    expect(p.completionRate(DateTime(2026, 5, 11), today), closeTo(0.5, 1e-9));
  });

  test('completionRate：间隔频率只统计需要打卡的日子', () {
    final p = Project(
      id: 'i',
      name: '隔三天',
      createdAt: DateTime(2026, 5, 11),
      frequencyType: FrequencyType.interval,
      intervalDays: 3,
    );
    // 需要打卡：5/11、5/14、5/17、5/20，其中打了 2 天
    add(p, 5, 11);
    add(p, 5, 17);
    expect(p.completionRate(DateTime(2026, 5, 11), today), closeTo(0.5, 1e-9));
  });

  test('completionRate：区间内没有需要打卡的日子时返回 0', () {
    final p = Project(
      id: 'w',
      name: '每周日',
      createdAt: DateTime(2026, 5, 1),
      frequencyType: FrequencyType.weekly,
      weeklyDays: const [7],
    );
    // 5/20 是周三，5/18~5/20 里没有周日
    expect(p.completionRate(DateTime(2026, 5, 18), today), 0);
  });
}
