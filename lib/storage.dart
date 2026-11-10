import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// 同一毫秒里连选几张图时，光靠时间戳会重名覆盖，再加个自增序号
  static int _imageSeq = 0;

  static Future<String> saveImage(String sourcePath) async {
    final source = File(sourcePath);

    // 只取文件名部分再找扩展名，路径里带点（比如 C:\a.b\photo）也不会取错
    final segments = source.uri.pathSegments;
    final baseName = segments.isEmpty ? sourcePath : segments.last;
    final dot = baseName.lastIndexOf('.');
    final rawExt = dot > 0 ? baseName.substring(dot + 1).toLowerCase() : '';
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(rawExt) ? rawExt : 'jpg';

    final target = File(await _uniqueImagePath(ext));
    await source.copy(target.path);
    return target.path;
  }

  /// images 目录里一个不重复的文件路径（时间戳 + 自增序号）
  static Future<String> _uniqueImagePath(String ext) async {
    final folder = await imagesFolderPath();
    _imageSeq++;
    final name = '${DateTime.now().millisecondsSinceEpoch}_$_imageSeq.$ext';
    return '$folder/$name';
  }

  /// 删除应用自己存的图片。只处理 images 目录里的文件，避免误删用户相册里的原图
  static Future<void> deleteImage(String path) async {
    try {
      final folder = await imagesFolderPath();
      if (!path.startsWith(folder)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('删除图片失败：$e');
    }
  }

  static Future<void> deleteImages(Iterable<String> paths) async {
    for (final path in paths.toList()) {
      await deleteImage(path);
    }
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

    // 记录里的图片存的是绝对路径，换了目录后要跟着改，否则历史图片全部打不开
    await _rebaseImagePaths(oldPath, newPath);
  }

  static Future<void> _rebaseImagePaths(String oldPath, String newPath) async {
    final projects = await loadProjects();
    var changed = false;
    for (final p in projects) {
      for (final r in p.records) {
        for (var i = 0; i < r.images.length; i++) {
          if (r.images[i].startsWith(oldPath)) {
            r.images[i] = r.images[i].replaceFirst(oldPath, newPath);
            changed = true;
          }
        }
      }
      // 自定义图标同样是绝对路径
      final icon = p.iconPath;
      if (icon.startsWith('file://')) {
        final path = icon.substring(7);
        if (path.startsWith(oldPath)) {
          p.iconPath = 'file://${path.replaceFirst(oldPath, newPath)}';
          changed = true;
        }
      }
    }
    if (changed) await saveProjects(projects);
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
    final data = await buildProjectArchive(p);
    final path = await dataFolderPath();
    final folder = Directory('$path/exports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File('${folder.path}/${data.fileName}');
    await file.writeAsBytes(data.bytes);
    return file.path;
  }

  /// 把项目和它引用的图片打成一个 zip：project.json + images/
  /// 换台机器导入时图片能一起带过去
  static Future<ProjectArchive> buildProjectArchive(Project p) async {
    final archive = Archive();
    final imageCount = await _addProjectTo(archive, p, prefix: '');
    final zipped = ZipEncoder().encode(archive);
    return ProjectArchive(
      fileName: _exportFileName(p),
      bytes: Uint8List.fromList(zipped),
      imageCount: imageCount,
    );
  }

  /// 一次导出全部项目：每个项目一个子目录，导入时能整包读回来
  static Future<ProjectArchive> buildAllProjectsArchive(
    List<Project> projects,
  ) async {
    final archive = Archive();
    final usedFolders = <String>{};
    var imageCount = 0;
    for (var i = 0; i < projects.length; i++) {
      final p = projects[i];
      var folder = _safeFolderName(p.name);
      var suffix = 1;
      while (!usedFolders.add(folder)) {
        folder = '${_safeFolderName(p.name)}(${suffix++})';
      }
      imageCount += await _addProjectTo(archive, p, prefix: '$folder/');
    }
    final zipped = ZipEncoder().encode(archive);
    return ProjectArchive(
      fileName: '打卡日历-全部项目-${_stamp()}.zip',
      bytes: Uint8List.fromList(zipped),
      imageCount: imageCount,
    );
  }

  /// 往包里塞一个项目，[prefix] 为空是单项目导出，否则是批量导出的子目录
  static Future<int> _addProjectTo(
    Archive archive,
    Project p, {
    required String prefix,
  }) async {
    final images = <String>{
      for (final r in p.records) ...r.images,
      if (p.iconPath.startsWith('file://')) p.iconPath.substring(7),
    };

    // 包内统一用 images/<文件名>，遇到重名再加序号
    final nameMap = <String, String>{};
    final used = <String>{};
    for (final path in images) {
      final base = _fileNameOf(path);
      var name = '${prefix}images/$base';
      var i = 1;
      while (!used.add(name)) {
        name = '${prefix}images/${i}_$base';
        i++;
      }
      nameMap[path] = name;
    }

    // 在副本上改路径，别把正在用的项目数据改坏了
    final copy = Project.fromJson(p.toJson());
    for (final r in copy.records) {
      r.images = [for (final path in r.images) nameMap[path] ?? path];
    }
    if (copy.iconPath.startsWith('file://')) {
      final name = nameMap[copy.iconPath.substring(7)];
      copy.iconPath = name == null ? '' : 'file://$name';
    }

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(copy.toJson()),
    );
    archive.addFile(
      ArchiveFile('${prefix}project.json', jsonBytes.length, jsonBytes),
    );

    var imageCount = 0;
    for (final entry in nameMap.entries) {
      final file = File(entry.key);
      if (!await file.exists()) continue; // 图片被清理过就跳过，别让整个导出失败
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(entry.value, bytes.length, bytes));
      imageCount++;
    }
    return imageCount;
  }

  /// 导出的结果：位置描述 + 是否在文件管理器里能看到
  static Future<ExportResult> exportProjectToPublic(Project p) async {
    final data = await buildProjectArchive(p);
    return _writeArchive(data);
  }

  /// 批量导出：所有项目打进同一个 zip
  static Future<ExportResult> exportAllToPublic(List<Project> projects) async {
    final data = await buildAllProjectsArchive(projects);
    return _writeArchive(data);
  }

  static const _exportDirKey = 'export_dir';

  /// 用户自己选的导出目录，返回空字符串表示用默认位置
  static Future<String> loadExportDir() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_exportDirKey) ?? '';
  }

  /// 传空字符串就是恢复默认位置
  static Future<void> saveExportDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.isEmpty) {
      await prefs.remove(_exportDirKey);
    } else {
      await prefs.setString(_exportDirKey, path);
    }
  }

  /// 选目录时先试写一下，免得选了个没有权限的地方，导出时才发现失败
  static Future<bool> canWriteTo(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File('${dir.path}/.checkin_write_probe');
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (e) {
      debugPrint('导出目录不可写：$e');
      return false;
    }
  }

  static Future<ExportResult> _writeArchive(ProjectArchive data) async {
    final name = data.fileName;
    final bytes = data.bytes;

    // 用户在设置里指定过目录就用它，写不进去再往下走默认逻辑
    final custom = await loadExportDir();
    if (custom.isNotEmpty) {
      try {
        final dir = Directory('$custom/$_exportFolder');
        await dir.create(recursive: true);
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes);
        return ExportResult(file.path,
            visible: true, imageCount: data.imageCount);
      } catch (e) {
        debugPrint('写入自定义导出目录失败，回退默认位置：$e');
      }
    }

    // Android：写进公共「下载/打卡日历导出/」，MediaStore 不需要权限
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final where = await _filesChannel.invokeMethod<String>(
          'saveToDownloads',
          {'name': name, 'bytes': bytes, 'mime': 'application/zip'},
        );
        if (where != null && where.isNotEmpty) {
          return ExportResult(where,
              visible: true, imageCount: data.imageCount);
        }
      } catch (e) {
        debugPrint('写入公共下载目录失败，回退到应用目录：$e');
      }
    }

    // 桌面：写到系统下载目录
    if (!kIsWeb && !Platform.isAndroid) {
      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final dir = Directory('${downloads.path}/$_exportFolder');
          await dir.create(recursive: true);
          final file = File('${dir.path}/$name');
          await file.writeAsBytes(bytes);
          return ExportResult(file.path,
              visible: true, imageCount: data.imageCount);
        }
      } catch (e) {
        debugPrint('写入下载目录失败，回退到应用目录：$e');
      }
    }

    // 兜底：应用私有目录（老系统或权限被拒时）
    final path = await dataFolderPath();
    final folder = Directory('$path/exports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes);
    return ExportResult(file.path, visible: false, imageCount: data.imageCount);
  }

  /// 导入自己导出的 zip；单个项目和批量导出的整包都能读，
  /// 早期版本导出的单个 json 也还能读
  static Future<List<ImportOutcome>> importProjectsFromFile(
    String sourcePath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (!isZip) {
      final project = Project.fromJson(jsonDecode(utf8.decode(bytes)));
      return [ImportOutcome(project, 0)];
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = [
      for (final file in archive.files)
        if (file.isFile && file.name.endsWith('project.json')) file,
    ];
    if (entries.isEmpty) throw const FormatException('压缩包里没有项目数据');

    final outcomes = <ImportOutcome>[];
    for (final entry in entries) {
      // 单项目导出的 project.json 在根目录，批量导出在 <项目名>/ 下
      final prefix =
          entry.name.substring(0, entry.name.length - 'project.json'.length);
      final project = Project.fromJson(
        jsonDecode(utf8.decode(entry.content as List<int>)),
      );

      // 包里的图片重新落盘，再把记录里的相对路径换成新的绝对路径
      final restored = <String, String>{};
      final imagePrefix = '${prefix}images/';
      for (final file in archive.files) {
        if (!file.isFile || !file.name.startsWith(imagePrefix)) continue;
        final saved = await _writeImageBytes(
          file.name.substring(imagePrefix.length),
          Uint8List.fromList(file.content as List<int>),
        );
        restored[file.name] = saved;
      }

      for (final r in project.records) {
        r.images = [for (final path in r.images) restored[path] ?? path];
      }
      if (project.iconPath.startsWith('file://')) {
        final saved = restored[project.iconPath.substring(7)];
        project.iconPath = saved == null ? '' : 'file://$saved';
      }

      outcomes.add(ImportOutcome(project, restored.length));
    }
    return outcomes;
  }

  /// 只关心一个项目时的简单封装
  static Future<ImportOutcome> importProjectFile(String sourcePath) async {
    final outcomes = await importProjectsFromFile(sourcePath);
    return outcomes.first;
  }

  /// 把一段图片字节写进 images 目录，名字保证不重复
  static Future<String> _writeImageBytes(String name, Uint8List bytes) async {
    final dot = name.lastIndexOf('.');
    final rawExt = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(rawExt) ? rawExt : 'jpg';
    final target = File(await _uniqueImagePath(ext));
    await target.writeAsBytes(bytes);
    return target.path;
  }

  static String _fileNameOf(String path) {
    final segments = Uri.file(path).pathSegments;
    return segments.isEmpty ? 'file' : segments.last;
  }

  static const MethodChannel _filesChannel =
      MethodChannel('com.yunluan.checkincalendar/files');

  /// 公共导出目录名，Android 上是「下载/打卡日历导出」
  static const String _exportFolder = '打卡日历导出';

  static String _exportFileName(Project p) {
    final safeName = p.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip';
  }

  /// 批量导出时的子目录名：去掉路径里不允许的字符
  static String _safeFolderName(String name) {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return safe.isEmpty ? '未命名项目' : safe;
  }

  /// 20261110-2230 这样的时间戳，用来给整包导出起名
  static String _stamp() {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
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

/// 导出结果
class ExportResult {
  const ExportResult(
    this.location, {
    required this.visible,
    this.imageCount = 0,
  });

  /// 给用户看的位置，例如「下载/打卡日历导出/晨间阅读_1712345.zip」
  final String location;

  /// true 表示在文件管理器里能直接找到；false 表示落在应用私有目录
  final bool visible;

  /// 一起打包进去的图片数量
  final int imageCount;
}

/// 打包好的项目备份
class ProjectArchive {
  const ProjectArchive({
    required this.fileName,
    required this.bytes,
    required this.imageCount,
  });

  final String fileName;
  final Uint8List bytes;
  final int imageCount;
}

/// 导入结果：项目本身 + 成功还原的图片数量
class ImportOutcome {
  const ImportOutcome(this.project, this.imageCount);

  final Project project;
  final int imageCount;
}
