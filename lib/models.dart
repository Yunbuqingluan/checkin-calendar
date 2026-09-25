enum FrequencyType { daily, interval, weekly, monthly }

class Metric {
  String id;
  String name;
  String unit;
  Metric({required this.id, required this.name, required this.unit});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'unit': unit};
  factory Metric.fromJson(Map<String, dynamic> json) =>
      Metric(id: json['id'], name: json['name'], unit: json['unit']);
}

class CheckInRecord {
  String id;
  DateTime time;
  String note;
  Map<String, double> metricValues;
  List<String> images;
  bool isMakeUp;

  CheckInRecord({
    required this.id,
    required this.time,
    this.note = '',
    Map<String, double>? metricValues,
    List<String>? images,
    this.isMakeUp = false,
  })  : metricValues = metricValues ?? {},
        images = images ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'note': note,
        'metricValues': metricValues,
        'images': images,
        'isMakeUp': isMakeUp,
      };

  factory CheckInRecord.fromJson(Map<String, dynamic> json) => CheckInRecord(
        id: json['id'],
        time: DateTime.parse(json['time']),
        note: json['note'] ?? '',
        metricValues: (json['metricValues'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            {},
        images: List<String>.from(json['images'] ?? []),
        isMakeUp: json['isMakeUp'] ?? false,
      );
}

class Project {
  String id;
  String name;
  String iconPath;
  DateTime createdAt;
  FrequencyType frequencyType;
  int intervalDays;
  List<int> weeklyDays;
  List<int> monthlyDays;
  int dailyLimit; // -1 无上限
  bool reminderOn;
  List<Metric> metrics;
  List<CheckInRecord> records;
  bool imported;

  Project({
    required this.id,
    required this.name,
    this.iconPath = '',
    required this.createdAt,
    this.frequencyType = FrequencyType.daily,
    this.intervalDays = 1,
    List<int>? weeklyDays,
    List<int>? monthlyDays,
    this.dailyLimit = 1,
    this.reminderOn = false,
    List<Metric>? metrics,
    List<CheckInRecord>? records,
    this.imported = false,
  })  : weeklyDays = weeklyDays ?? [],
        monthlyDays = monthlyDays ?? [],
        metrics = metrics ?? [],
        records = records ?? [];

  bool isRequiredOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (d.isBefore(start)) return false;
    switch (frequencyType) {
      case FrequencyType.daily:
        return true;
      case FrequencyType.interval:
        return d.difference(start).inDays % intervalDays == 0;
      case FrequencyType.weekly:
        return weeklyDays.contains(d.weekday);
      case FrequencyType.monthly:
        return monthlyDays.contains(d.day);
    }
  }

  List<CheckInRecord> recordsOn(DateTime day) => records
      .where((r) =>
          r.time.year == day.year &&
          r.time.month == day.month &&
          r.time.day == day.day)
      .toList();

  bool isCheckedOn(DateTime day) => recordsOn(day).isNotEmpty;

  bool isMakeUpOn(DateTime day) {
    final list = recordsOn(day);
    return list.isNotEmpty && list.every((r) => r.isMakeUp);
  }

  bool reachedLimitOn(DateTime day) {
    if (dailyLimit == -1) return false;
    return recordsOn(day).length >= dailyLimit;
  }

  /// 根据 id 找指标
  Metric? findMetric(String id) {
    for (final m in metrics) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<MapEntry<DateTime, double>> metricPoints(
      String metricId, DateTime? cutoff) {
    final list = <MapEntry<DateTime, double>>[];
    for (final r in records) {
      if (cutoff != null && r.time.isBefore(cutoff)) continue;
      final v = r.metricValues[metricId];
      if (v != null) list.add(MapEntry(r.time, v));
    }
    list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconPath': iconPath,
        'createdAt': createdAt.toIso8601String(),
        'frequencyType': frequencyType.name,
        'intervalDays': intervalDays,
        'weeklyDays': weeklyDays,
        'monthlyDays': monthlyDays,
        'dailyLimit': dailyLimit,
        'reminderOn': reminderOn,
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'imported': imported,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'],
        name: json['name'],
        iconPath: json['iconPath'] ?? '',
        createdAt: DateTime.parse(json['createdAt']),
        frequencyType: FrequencyType.values.firstWhere(
          (e) => e.name == json['frequencyType'],
          orElse: () => FrequencyType.daily,
        ),
        intervalDays: json['intervalDays'] ?? 1,
        weeklyDays: List<int>.from(json['weeklyDays'] ?? []),
        monthlyDays: List<int>.from(json['monthlyDays'] ?? []),
        dailyLimit: json['dailyLimit'] ?? 1,
        reminderOn: json['reminderOn'] ?? false,
        metrics: (json['metrics'] as List?)
                ?.map((e) => Metric.fromJson(e))
                .toList() ??
            [],
        records: (json['records'] as List?)
                ?.map((e) => CheckInRecord.fromJson(e))
                .toList() ??
            [],
        imported: json['imported'] ?? false,
      );
}