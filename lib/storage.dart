import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'notification_service.dart';

class Storage {
  static const _fileName = 'projects.json';
  static const _prefKey = 'data_dir';

  static Future<String> dataFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_prefKey);
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (!await dir.exists()) await dir.create(recursive: true);
      return custom;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/checkin_app';
    final folder = Directory(path);
    if (!await folder.exists()) await folder.create(recursive: true);
    return path;
  }

  static Future<File> _getFile() async {
    final path = await dataFolderPath();
    return File('$path/$_fileName');
  }

  static Future<String> imagesFolderPath() async {
    final path = await dataFolderPath();
    final folder = Directory('$path/images');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder.path;
  }

  static Future<String> saveImage(String sourcePath) async {
    final folder = await imagesFolderPath();
    final ext = sourcePath.split('.').last;
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final target = File('$folder/$name');
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  static Future<void> changeDataDir(String newPath) async {
    final oldPath = await dataFolderPath();
    if (oldPath == newPath) return;

    final oldDir = Directory(oldPath);
    final newDir = Directory(newPath);
    if (!await newDir.exists()) await newDir.create(recursive: true);

    if (await oldDir.exists()) {
      await for (final entity in oldDir.list()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final target = File('${newDir.path}/$name');
        if (entity is File) {
          await entity.copy(target.path);
          await entity.delete();
        } else if (entity is Directory) {
          await _copyDir(entity, Directory(target.path));
          await entity.delete(recursive: true);
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, newPath);
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    if (!await to.exists()) await to.create(recursive: true);
    await for (final entity in from.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is File) {
        await entity.copy('${to.path}/$name');
      } else if (entity is Directory) {
        await _copyDir(entity, Directory('${to.path}/$name'));
      }
    }
  }

  static Future<List<Project>> loadProjects() async {
    try {
      final file = await _getFile();
      // 主文件读不出来时退回上一份备份，避免一次写坏就丢掉全部数据
      for (final candidate in [file, File('${file.path}.bak')]) {
        try {
          if (!await candidate.exists()) continue;
          final list = jsonDecode(await candidate.readAsString());
          if (list is! List) continue;
          return list
              .map((e) => Project.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      // 数据目录拿不到（比如测试环境或权限异常）时按空数据处理，不能让首页卡在加载中
      debugPrint('读取数据目录失败：$e');
    }
    return [];
  }

  static Future<void> saveProjects(List<Project> projects) async {
    final file = await _getFile();
    final content = jsonEncode(projects.map((p) => p.toJson()).toList());

    // 先写临时文件并落盘，再把旧文件留一份 .bak，最后原子替换。
    // 中途断电最多丢掉最后一次改动，不会出现半个 JSON。
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
    }
    await tmp.rename(file.path);

    // 数据一改，提醒的排期就要跟着变（当天已打卡的会被跳过）
    unawaited(NotificationService.syncAll(projects));
  }

  static Future<String> exportProject(Project p) async {
    final path = await dataFolderPath();
    final folder = Directory('$path/exports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final safeName = p.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(
        '${folder.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(p.toJson()));
    return file.path;
  }

  static const presetIcons = [
    'morning.webp',
    'reading.webp',
    'fitness.webp',
    'running.webp',
    'water.webp',
    'sleep.webp',
    'meditation.webp',
    'study.webp',
    'writing.webp',
    'drawing.webp',
    'diet.webp',
    'accounting.webp',
    'quit_smoking.webp',
    'piano.webp',
    'cooking.webp',
    'medicine.webp',
  ];

  /// 旧版本数据里存的是 .png 文件名，图标已统一压成 .webp，这里兼容一下
  static String iconAsset(String name) => name.endsWith('.png')
      ? '${name.substring(0, name.length - 4)}.webp'
      : name;
}