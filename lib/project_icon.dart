import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';

/// 项目图标：预设图标走 assets，上传的图片走本地文件，没有图标就用名字首字。
class ProjectIcon extends StatelessWidget {
  const ProjectIcon({
    super.key,
    required this.project,
    this.size = 44,
  });

  final Project project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        project.name.isEmpty ? '?' : project.name.characters.first,
        style: TextStyle(
          fontSize: size * 0.42,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );

    if (project.iconPath.isEmpty) return fallback;

    Widget image;
    if (project.iconPath.startsWith('file://')) {
      final path = project.iconPath.substring(7);
      image = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      image = Image.asset(
        'assets/icons/${Storage.iconAsset(project.iconPath)}',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return ClipOval(
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}
