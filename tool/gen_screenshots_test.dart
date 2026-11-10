// 生成 README 用的截图。
//
// 跑：flutter test tool/gen_screenshots_test.dart
// 中文用系统字体（Windows 的 SimHei）渲染，Web 构建拿不到中文字体，只能本地渲染。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar_app/app_theme.dart';
import 'package:my_calendar_app/home_page.dart';
import 'package:my_calendar_app/main_preview.dart';
import 'package:my_calendar_app/overview_page.dart';
import 'package:my_calendar_app/project_detail_page.dart';

const _fontFamily = 'ScreenshotCJK';
const _outDir = 'docs/screenshots';
const _pageSize = Size(390, 844);
const _pixelRatio = 2.0;

Future<String> _loadCjkFont() async {
  const candidates = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\simsun.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(_fontFamily)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    return path;
  }
  throw StateError('找不到可用的中文字体');
}

ThemeData _theme({String? fontFamily}) => buildAppTheme(
      seed: AppColors.pink,
      brightness: Brightness.light,
      fontFamily: fontFamily,
    );

Future<Uint8List> _renderPng(
  WidgetTester tester,
  Widget page, {
  String? fontFamily,
}) async {
  tester.view.physicalSize = _pageSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(fontFamily: fontFamily),
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

Future<void> _capture(WidgetTester tester, Widget page, String fileName) async {
  final bytes = await _renderPng(tester, page, fontFamily: _fontFamily);
  final dir = Directory(_outDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$_outDir/$fileName.png').writeAsBytesSync(bytes);
}

void main() {
  setUpAll(() async {
    final path = await _loadCjkFont();
    // ignore: avoid_print
    print('使用字体: $path');
  });

  testWidgets('中文字体确实生效', (tester) async {
    final page =
        HomePage(initialProjects: demoProjects(), enableOnboarding: false);
    final withFont = await _renderPng(tester, page, fontFamily: _fontFamily);
    final withoutFont = await _renderPng(tester, page);
    var diff = 0;
    final n = withFont.length < withoutFont.length
        ? withFont.length
        : withoutFont.length;
    for (var i = 0; i < n; i++) {
      if (withFont[i] != withoutFont[i]) diff++;
    }
    // ignore: avoid_print
    print('字体对比: 字节差异 $diff / $n');
    expect(diff, greaterThan(n ~/ 100), reason: '中文字体没加载成功');
  });

  testWidgets('首页', (tester) async {
    await _capture(
      tester,
      HomePage(initialProjects: demoProjects(), enableOnboarding: false),
      'home',
    );
  });

  testWidgets('详情页', (tester) async {
    await _capture(
      tester,
      ProjectDetailPage(project: demoProjects().first),
      'detail',
    );
  });

  testWidgets('统计总览', (tester) async {
    await _capture(
      tester,
      OverviewPage(projects: demoProjects(), onChanged: () {}),
      'overview',
    );
  });

  testWidgets('主界面引导', (tester) async {
    await _capture(
      tester,
      HomePage(
        initialProjects: demoProjects(),
        enableOnboarding: false,
        alwaysShowGuide: true,
      ),
      'guide',
    );
  });
}
