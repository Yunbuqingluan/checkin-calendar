import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

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
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return list.map((e) => Project.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveProjects(List<Project> projects) async {
    final file = await _getFile();
    await file.writeAsString(
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
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
    'morning.png',
    'reading.png',
    'fitness.png',
    'running.png',
    'water.png',
    'sleep.png',
    'meditation.png',
    'study.png',
    'writing.png',
    'drawing.png',
    'diet.png',
    'accounting.png',
    'quit_smoking.png',
    'piano.png',
    'cooking.png',
    'medicine.png',
  ];
}