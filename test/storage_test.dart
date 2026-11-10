import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('导出成 zip，项目数据和图片都在里面', () async {
    final image = File('${tempDir.path}/checkin_app/images/r1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);

    final p = Project(
      id: 'x',
      name: '晨间阅读',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'r1',
          time: DateTime(2026, 5, 2, 8),
          images: [image.path],
        ),
      ],
    );

    final result = await Storage.exportProjectToPublic(p);

    expect(result.visible, isTrue);
    expect(result.location, contains('打卡日历导出'));
    expect(result.location, endsWith('.zip'));
    expect(result.imageCount, 1);

    final archive =
        ZipDecoder().decodeBytes(File(result.location).readAsBytesSync());
    final jsonFile = archive.files.firstWhere((f) => f.name == 'project.json');
    final json = jsonDecode(utf8.decode(jsonFile.content as List<int>))
        as Map<String, dynamic>;

    expect(json['name'], '晨间阅读');
    final record = (json['records'] as List).single as Map<String, dynamic>;
    // 包里存的是相对路径，换机器也能对上
    expect(record['images'], ['images/r1.jpg']);
    expect(
      archive.files.where((f) => f.name.startsWith('images/')),
      hasLength(1),
    );
  });

  test('项目名里的非法字符会被替换掉', () async {
    final p = Project(id: 'y', name: 'a/b:c*?', createdAt: DateTime(2026, 5, 1));

    final result = await Storage.exportProjectToPublic(p);
    // 只看文件名，别把 Windows 盘符的冒号算进去
    final fileName = result.location.split(RegExp(r'[\\/]')).last;

    expect(fileName, startsWith('a_b_c__'));
    expect(fileName, isNot(contains(':')));
    expect(fileName, isNot(contains('/')));
    expect(fileName, endsWith('.zip'));
  });

  test('导出的 zip 自带图片，换机器导入后图片还能打开', () async {
    final image = File('${tempDir.path}/checkin_app/images/r1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([7, 8, 9]);

    final p = Project(
      id: 'p1',
      name: '晨间阅读',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'r1',
          time: DateTime(2026, 5, 2, 8),
          note: '今天读了 20 页',
          images: [image.path],
        ),
      ],
    );
    await Storage.saveProjects([p]);

    final zipPath = await Storage.exportProject(p);
    // 原图删掉，模拟「换了台手机」
    image.deleteSync();

    final outcome = await Storage.importProjectFile(zipPath);
    final restored = outcome.project.records.single.images.single;

    expect(outcome.imageCount, 1);
    expect(File(restored).existsSync(), isTrue);
    expect(File(restored).readAsBytesSync(), [7, 8, 9]);
    expect(outcome.project.records.single.note, '今天读了 20 页');
    expect(restored, contains('images'));
  });

  test('回退到应用目录时 visible 为 false', () async {
    final p = Project(id: 'z', name: '夜跑', createdAt: DateTime(2026, 5, 1));

    final result = await Storage.exportProject(p);

    final file = File(result);
    expect(file.existsSync(), isTrue);
    expect(result, contains('exports'));
  });

  test('连续保存多张图片不会互相覆盖', () async {
    final src = File('${tempDir.path}/photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);

    final paths = <String>[];
    for (var i = 0; i < 5; i++) {
      paths.add(await Storage.saveImage(src.path));
    }

    expect(paths.toSet(), hasLength(5));
    for (final path in paths) {
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      // 都落在数据目录的 images 里，扩展名保持 jpg
      expect(path, contains('images'));
      expect(path, endsWith('.jpg'));
    }
  });

  test('文件没有扩展名时也能存下来', () async {
    final src = File('${tempDir.path}/noext')..writeAsBytesSync([9]);

    final saved = await Storage.saveImage(src.path);

    expect(File(saved).existsSync(), isTrue);
    expect(saved, endsWith('.jpg'));
  });

  test('删图片只删数据目录里的，用户原图不动', () async {
    final inside = File('${tempDir.path}/checkin_app/images/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    final outside = File('${tempDir.path}/outside.jpg')
      ..writeAsBytesSync([2]);

    await Storage.deleteImage(inside.path);
    await Storage.deleteImage(outside.path);
    await Storage.deleteImage('${tempDir.path}/checkin_app/images/none.jpg');

    expect(inside.existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
  });

  test('换数据目录后图片路径跟着改，图片还能打开', () async {
    final oldDir = '${tempDir.path}/checkin_app';
    final image = File('$oldDir/images/r1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([7]);

    final p = Project(
      id: 'p1',
      name: '晨间阅读',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'r1',
          time: DateTime(2026, 5, 2, 8),
          images: [image.path],
        ),
      ],
    );
    await Storage.saveProjects([p]);

    final newDir = '${tempDir.path}/moved';
    await Storage.changeDataDir(newDir);

    final loaded = await Storage.loadProjects();
    final path = loaded.single.records.single.images.single;

    expect(path, startsWith(newDir));
    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsBytesSync(), [7]);
  });

  test('批量导出：每个项目一个子目录，图片跟着各自的目录走', () async {
    final img1 = File('${tempDir.path}/checkin_app/images/a1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 1, 1]);
    final img2 = File('${tempDir.path}/checkin_app/images/b1.jpg')
      ..writeAsBytesSync([2, 2, 2]);

    final a = Project(
      id: 'a',
      name: '晨间阅读',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'ra',
          time: DateTime(2026, 5, 2, 8),
          images: [img1.path],
        ),
      ],
    );
    final b = Project(
      id: 'b',
      name: '夜跑',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'rb',
          time: DateTime(2026, 5, 3, 21),
          images: [img2.path],
        ),
      ],
    );

    final data = await Storage.buildAllProjectsArchive([a, b]);
    final archive = ZipDecoder().decodeBytes(data.bytes);
    final names = archive.files.map((f) => f.name).toList();

    expect(names, contains('晨间阅读/project.json'));
    expect(names, contains('夜跑/project.json'));
    expect(names.where((n) => n.endsWith('.json')), hasLength(2));
    expect(names.where((n) => n.contains('/images/')), hasLength(2));
    expect(data.imageCount, 2);
    expect(data.fileName, endsWith('.zip'));

    // 记录里的图片写成带目录的相对路径
    final entry =
        archive.files.firstWhere((f) => f.name == '夜跑/project.json');
    final json = jsonDecode(utf8.decode(entry.content as List<int>)) as Map;
    final records = json['records'] as List;
    final images = (records.single as Map)['images'] as List;
    expect(images.single.toString(), startsWith('夜跑/images/'));
  });

  test('批量导出的整包能一次读回多个项目，图片也会重新落盘', () async {
    final img1 = File('${tempDir.path}/checkin_app/images/c1.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);
    final img2 = File('${tempDir.path}/checkin_app/images/c2.jpg')
      ..writeAsBytesSync([3, 3]);

    final a = Project(
      id: 'a',
      name: '喝水',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'r1',
          time: DateTime(2026, 5, 2, 9),
          images: [img1.path],
        ),
      ],
    );
    final b = Project(
      id: 'b',
      name: '夜跑',
      createdAt: DateTime(2026, 5, 1),
      records: [
        CheckInRecord(
          id: 'r2',
          time: DateTime(2026, 5, 2, 21),
          images: [img2.path],
        ),
      ],
    );

    final data = await Storage.buildAllProjectsArchive([a, b]);
    final zip = File('${tempDir.path}/all.zip')
      ..writeAsBytesSync(data.bytes);
    img1.deleteSync();
    img2.deleteSync();

    final outcomes = await Storage.importProjectsFromFile(zip.path);

    expect(outcomes, hasLength(2));
    expect(outcomes.map((o) => o.project.name), containsAll(['喝水', '夜跑']));
    expect(outcomes.map((o) => o.imageCount).reduce((x, y) => x + y), 2);
    for (final outcome in outcomes) {
      final path = outcome.project.records.single.images.single;
      expect(File(path).existsSync(), isTrue);
    }
  });

  test('单个项目的老 zip 仍然可以导入', () async {
    final p = Project(id: 's', name: '冥想', createdAt: DateTime(2026, 5, 1));
    final data = await Storage.buildProjectArchive(p);
    final zip = File('${tempDir.path}/single.zip')
      ..writeAsBytesSync(data.bytes);

    final outcomes = await Storage.importProjectsFromFile(zip.path);

    expect(outcomes, hasLength(1));
    expect(outcomes.single.project.name, '冥想');
  });
  test('设置里改了导出位置，zip 就写到那个目录下面', () async {
    final p = Project(id: 'q', name: '拉伸', createdAt: DateTime(2026, 5, 1));
    final custom = Directory('${tempDir.path}/我的导出')..createSync();

    await Storage.saveExportDir(custom.path);
    expect(await Storage.loadExportDir(), custom.path);
    expect(await Storage.canWriteTo(custom.path), isTrue);

    final result = await Storage.exportProjectToPublic(p);

    expect(result.location, contains('我的导出'));
    expect(result.visible, isTrue);
    expect(File(result.location).existsSync(), isTrue);
    expect(result.location, contains('打卡日历导出'));
  });

  test('导出位置可以恢复默认', () async {
    final p = Project(id: 'r', name: '早睡', createdAt: DateTime(2026, 5, 1));
    final custom = Directory('${tempDir.path}/另一个位置')..createSync();
    await Storage.saveExportDir(custom.path);

    await Storage.saveExportDir('');
    expect(await Storage.loadExportDir(), isEmpty);

    final result = await Storage.exportProjectToPublic(p);
    expect(result.location, isNot(contains('另一个位置')));
    expect(File(result.location).existsSync(), isTrue);
  });
}
