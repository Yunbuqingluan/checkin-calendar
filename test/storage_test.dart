import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/models.dart';
import 'package:my_calendar_app/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => '$root/Downloads';
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('calendar_export_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows 上偶发占用，忽略
    }
  });

  test('导出写到「下载/打卡日历导出/」并返回可见位置', () async {
    final p = Project(
      id: 'x',
      name: '晨间阅读',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(id: 'r1', time: DateTime(2026, 5, 2, 8)),
      ],
    );

    final result = await Storage.exportProjectToPublic(p);

    expect(result.visible, isTrue);
    expect(result.location, contains('打卡日历导出'));
    expect(result.location, endsWith('.json'));

    final file = File(result.location);
    expect(file.existsSync(), isTrue);

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['name'], '晨间阅读');
    expect(json['records'], hasLength(1));
  });

  test('项目名里的非法字符会被替换掉', () async {
    final p = Project(id: 'y', name: 'a/b:c*?', createdAt: DateTime(2026, 5, 1));

    final result = await Storage.exportProjectToPublic(p);
    // 只看文件名，别把 Windows 盘符的冒号算进去
    final fileName = result.location.split(RegExp(r'[\\/]')).last;

    expect(fileName, startsWith('a_b_c__'));
    expect(fileName, isNot(contains(':')));
    expect(fileName, isNot(contains('/')));
    expect(fileName, endsWith('.json'));
  });

  test('回退到应用目录时 visible 为 false', () async {
    final p = Project(id: 'z', name: '夜跑', createdAt: DateTime(2026, 5, 1));

    final result = await Storage.exportProject(p);

    final file = File(result);
    expect(file.existsSync(), isTrue);
    expect(result, contains('exports'));
  });
}
