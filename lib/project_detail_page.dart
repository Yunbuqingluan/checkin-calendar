import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'compare_chart.dart';
import 'app_theme.dart';
import 'models.dart';
import 'storage.dart';

class ProjectDetailPage extends StatefulWidget {
  final Project project;
  const ProjectDetailPage({super.key, required this.project});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late DateTime _month;
  DateTime? _selectedDay;
  Offset? _lastLongPressPos; // 记录长按位置

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 单条打卡记录：补打卡用暖黄，正常打卡用薄荷绿
  Widget _recordTile(CheckInRecord r) {
    final accent = r.isMakeUp ? AppColors.mango : AppColors.mint;
    final timeText =
        '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}';
    final metricText = _metricTextOf(r);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTapDown: (d) => _lastLongPressPos = d.globalPosition,
        onLongPress: () =>
            _onRecordLongPress(r, _lastLongPressPos ?? Offset.zero),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  r.isMakeUp
                      ? Icons.edit_calendar_rounded
                      : Icons.check_rounded,
                  size: 17,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.isMakeUp ? '补打卡' : timeText,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    if (r.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.note,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                    if (metricText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metricText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                    if (r.images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: r.images
                            .map(
                              (path) => GestureDetector(
                                onTap: () => _showImage(path),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(path),
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 64,
                                      height: 64,
                                      color: Colors.grey.shade300,
                                      child: const Icon(
                                        Icons.broken_image_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color? _dayColor(DateTime day) {    final p = widget.project;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(p.createdAt.year, p.createdAt.month, p.createdAt.day);
    if (d.isBefore(start)) return null;
    if (p.isCheckedOn(d)) {
      return p.isMakeUpOn(d) ? AppColors.mango : AppColors.mint;
    }
    if (p.isRequiredOn(d)) {
      if (d.isBefore(today)) return AppColors.coral;
      if (_sameDay(d, today)) return AppColors.inkSoft;
    }
    return null;
  }

  Future<DateTime> _handleCrossDay(DateTime day) async {
    final now = DateTime.now();
    if (now.hour == 0 && now.minute <= 30) {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('跨天打卡'),
          content: const Text('现在是凌晨 0:00~0:30，这次打卡算作前一天吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('算作今天'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('算作前一天'),
            ),
          ],
        ),
      );
      if (result == true) {
        final prev = day.subtract(const Duration(days: 1));
        return DateTime(prev.year, prev.month, prev.day, 23, 59);
      }
    }
    return DateTime(day.year, day.month, day.day, now.hour, now.minute);
  }

  Future<List<String>> _pickImages(List<String> existing) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return existing;
    final newPaths = List<String>.from(existing);
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      try {
        final saved = await Storage.saveImage(path);
        if (!newPaths.contains(saved)) newPaths.add(saved);
      } catch (e) {
        debugPrint('保存图片失败：$e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('有图片没能保存，可能原文件已经被移走')),
          );
        }
      }
    }
    return newPaths;
  }

  /// 打卡弹窗里的图片缩略图：点开看大图，右上角小红点删除
  Widget _imageThumb({
    required String path,
    required VoidCallback onRemove,
    required VoidCallback onPreview,
  }) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(path),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 72,
                  height: 72,
                  color: AppColors.tint(AppColors.inkSoft, 0.14),
                  child: const Icon(
                    Icons.broken_image_rounded,
                    size: 22,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.pink,
                  shape: BoxShape.circle,
                  boxShadow: AppShadow.soft(AppColors.pink, opacity: 0.35),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addImageTile({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.tint(AppColors.pink, 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.pink.withValues(alpha: 0.35),
            width: 1.4,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_rounded,
              size: 20,
              color: AppColors.pink,
            ),
            SizedBox(height: 3),
            Text(
              '添加图片',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.pink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkInDialog(DateTime day,
      {bool isMakeUp = false, CheckInRecord? editRecord}) async {
    final noteCtrl = TextEditingController(text: editRecord?.note ?? '');
    final Map<String, TextEditingController> metricCtrls = {
      for (final m in widget.project.metrics)
        m.id: TextEditingController(
          text: editRecord?.metricValues[m.id]?.toString() ?? '',
        ),
    };
    List<String> images = List.from(editRecord?.images ?? []);
    // 打开弹窗时的原图，用来在确认后删掉被移除的；
    // addedImages 记录这次新复制进来的，取消时一并清掉
    final originalImages = List<String>.from(images);
    final addedImages = <String>[];
    final now = DateTime.now();

    // 这一天已经打满上限时，补打卡也不能再放行
    if (editRecord == null && widget.project.reachedLimitOn(day)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${day.month}月${day.day}日已经达到打卡上限'),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final title =
              editRecord != null ? '编辑打卡' : (isMakeUp ? '补打卡' : '打卡');
          final dayText =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          final timeText =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          final accent = isMakeUp ? AppColors.mango : AppColors.mint;

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            title: Row(
              children: [
                IconBubble(
                  size: 38,
                  color: AppColors.tint(accent, 0.20),
                  child: Icon(
                    isMakeUp
                        ? Icons.edit_calendar_rounded
                        : Icons.check_circle_rounded,
                    size: 19,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (editRecord == null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.tint(AppColors.sky, 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 14,
                              color: AppColors.sky,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isMakeUp ? '补记 $dayText' : '$dayText $timeText',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '备注（可选）',
                        hintText: '今天感觉怎么样',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (widget.project.metrics.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '数据指标',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...widget.project.metrics.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: metricCtrls[m.id],
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText:
                                    '${m.name}${m.unit.isNotEmpty ? ' (${m.unit})' : ''}',
                              ),
                            ),
                          )),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          '图片',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          images.isEmpty ? '可选' : '${images.length} 张',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final path in images)
                          _imageThumb(
                            path: path,
                            onRemove: () => setSt(() => images.remove(path)),
                            onPreview: () => _showImage(path),
                          ),
                        _addImageTile(
                          onTap: () async {
                            final res = await _pickImages(images);
                            addedImages.addAll(
                                res.where((p) => !images.contains(p)));
                            setSt(() => images = res);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      // 取消了就把这次刚复制进来的图片删掉，别在数据目录里留垃圾
      await Storage.deleteImages(addedImages);
      return;
    }

    // 编辑时被移除的旧图片，确认之后才真正从磁盘删
    await Storage.deleteImages(
      originalImages.where((p) => !images.contains(p)),
    );

    final metricValues = <String, double>{};
    metricCtrls.forEach((id, ctrl) {
      final v = double.tryParse(ctrl.text);
      if (v != null) metricValues[id] = v;
    });

    if (editRecord != null) {
      setState(() {
        editRecord.note = noteCtrl.text.trim();
        editRecord.metricValues = metricValues;
        editRecord.images = images;
      });
    } else {
      // 补打卡只记日期（当天 00:00），不把「现在几点」写进历史记录
      final actualTime = isMakeUp
          ? DateTime(day.year, day.month, day.day)
          : await _handleCrossDay(day);

      final record = CheckInRecord(
        id: now.millisecondsSinceEpoch.toString(),
        time: actualTime,
        note: noteCtrl.text.trim(),
        metricValues: metricValues,
        images: images,
        isMakeUp: isMakeUp,
      );
      widget.project.records.add(record);
      setState(() {});
    }
  }

  Future<void> _pickDateAndCheckIn() async {
    DateTime pickMonth = DateTime(_month.year, _month.month);
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final daysInMonth =
              DateTime(pickMonth.year, pickMonth.month + 1, 0).day;
          final firstWeekday =
              DateTime(pickMonth.year, pickMonth.month, 1).weekday;
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setSt(() {
                    pickMonth = DateTime(pickMonth.year, pickMonth.month - 1);
                  }),
                ),
                Text('${pickMonth.year}年${pickMonth.month}月'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setSt(() {
                    pickMonth = DateTime(pickMonth.year, pickMonth.month + 1);
                  }),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemCount: (firstWeekday - 1) + daysInMonth,
                itemBuilder: (ctx, i) {
                  if (i < firstWeekday - 1) return const SizedBox();
                  final dayNum = i - (firstWeekday - 1) + 1;
                  final day =
                      DateTime(pickMonth.year, pickMonth.month, dayNum);
                  final isFuture = day.isAfter(today0);
                  final isFull = widget.project.reachedLimitOn(day);
                  final disabled = isFuture || isFull;
                  return InkWell(
                    onTap: disabled
                        ? () => ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(isFuture ? '还没到那一天' : '这天已经达到打卡上限'),
                                duration: const Duration(seconds: 1),
                              ),
                            )
                        : () => Navigator.pop(ctx, day),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isFull
                            ? Colors.grey.withValues(alpha: 0.15)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$dayNum',
                          style: TextStyle(
                            color: disabled ? Colors.grey : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
    if (picked != null) await _checkInDialog(picked, isMakeUp: true);
  }

  Future<void> _onRecordLongPress(CheckInRecord r, Offset globalPos) async {
    final accent = r.isMakeUp ? AppColors.mango : AppColors.mint;
    final timeText =
        '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}';
    final result = await showActionSheet(
      context,
      title: r.isMakeUp ? '补打卡记录' : '打卡记录',
      subtitle:
          '${r.time.year}-${r.time.month.toString().padLeft(2, '0')}-${r.time.day.toString().padLeft(2, '0')} $timeText',
      leading: IconBubble(
        size: 44,
        color: AppColors.tint(accent, 0.16),
        child: Icon(
          r.isMakeUp ? Icons.edit_calendar_rounded : Icons.check_rounded,
          size: 22,
          color: accent,
        ),
      ),
      actions: [
        ActionSheetItem(
          value: 'edit',
          label: '编辑这条记录',
          description: '时间、备注、指标和图片都能改',
          icon: Icons.edit_rounded,
          color: AppColors.sky,
        ),
        ActionSheetItem(
          value: 'delete',
          label: '删除这条记录',
          description: '这条记录的备注图片也会一起清掉',
          icon: Icons.delete_outline_rounded,
          color: AppColors.pink,
          danger: true,
        ),
      ],
    );

    if (result == null) return;
    if (result == 'edit') {
      await _checkInDialog(r.time, editRecord: r);
    } else if (result == 'delete') {
      final images = List<String>.from(r.images);
      setState(() => widget.project.records.remove(r));
      // 记录删了，它带的备注图片也没人引用了，一起清掉
      await Storage.deleteImages(images);
    }
  }

  void _showImage(String path) {
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张图片已经不在了，可能被清理掉了')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InteractiveViewer(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(32),
                child: Icon(Icons.broken_image_rounded, size: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showStatsDialog() {
    if (widget.project.metrics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个项目还没有数据指标，先编辑项目添加')),
      );
      return;
    }

    int metricIndex = 0;
    int timeRange = 0;
    int chartType = 0;
    bool compare = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final metric = widget.project.metrics[metricIndex];
          final accent = AppColors.of(widget.project.id);
          final now = DateTime.now();
          DateTime? cutoff;
          if (timeRange == 1) {
            cutoff = now.subtract(const Duration(days: 7));
          } else if (timeRange == 2) {
            cutoff = now.subtract(const Duration(days: 30));
          } else if (timeRange == 3) {
            cutoff = DateTime(now.year, now.month, 1);
          }

          final points = widget.project.metricPoints(metric.id, cutoff);
          final values = points.map((e) => e.value).toList();
          final avg = values.isEmpty
              ? 0.0
              : values.reduce((a, b) => a + b) / values.length;
          final maxV =
              values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
          final minV =
              values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);

          const palette = <Color>[
            AppColors.pink,
            AppColors.sky,
            AppColors.mango,
            AppColors.mint,
            AppColors.grape,
            AppColors.coral,
          ];
          final series = <CompareSeries>[];
          if (compare) {
            for (var i = 0; i < widget.project.metrics.length; i++) {
              final m = widget.project.metrics[i];
              final pts = widget.project.metricPoints(m.id, cutoff);
              if (pts.isEmpty) continue;
              series.add(CompareSeries(
                name: m.name,
                unit: m.unit,
                color: palette[i % palette.length],
                points: pts,
              ));
            }
          }

          Widget chart;
          if (compare) {
            chart = series.isEmpty
                ? const _ChartEmptyHint()
                : Column(
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final s in series)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  s.unit.isEmpty
                                      ? s.name
                                      : '${s.name}(${s.unit})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: CompareChartPainter(series: series),
                        ),
                      ),
                      const Text(
                        '各指标按自身范围归一化，只比较趋势',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  );
          } else if (points.isEmpty) {
            chart = const _ChartEmptyHint();
          } else {
            chart = CustomPaint(
              size: Size.infinite,
              painter: chartType == 0
                  ? _LineChartPainter(
                      points: points,
                      unit: metric.unit,
                      color: accent,
                    )
                  : _BarChartPainter(
                      points: points,
                      unit: metric.unit,
                      color: accent,
                    ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
            child: Container(
              width: 520,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                boxShadow: AppShadow.lift,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconBubble(
                          size: 42,
                          color: AppColors.tint(accent, 0.16),
                          child: Icon(
                            Icons.insights_rounded,
                            size: 21,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${metric.name} 统计',
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                points.isEmpty
                                    ? '这个时间段还没有数据'
                                    : '共 ${points.length} 条 · 平均 ${_shortNumber(avg)}${metric.unit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: AppColors.creamDeep,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < 4; i++)
                          _ChartChip(
                            label: ['全部', '7 天', '30 天', '本月'][i],
                            selected: timeRange == i,
                            color: accent,
                            onTap: () => setSt(() => timeRange = i),
                          ),
                      ],
                    ),
                    if (widget.project.metrics.length > 1) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0;
                              i < widget.project.metrics.length;
                              i++)
                            _ChartChip(
                              label: widget.project.metrics[i].name,
                              selected: !compare && metricIndex == i,
                              color: accent,
                              onTap: () => setSt(() {
                                compare = false;
                                metricIndex = i;
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (widget.project.metrics.length > 1)
                          _ChartChip(
                            label: '多指标对比',
                            selected: compare,
                            color: AppColors.grape,
                            onTap: () => setSt(() => compare = !compare),
                          ),
                        if (!compare) ...[
                          _ChartChip(
                            label: '折线',
                            selected: chartType == 0,
                            color: accent,
                            onTap: () => setSt(() => chartType = 0),
                          ),
                          _ChartChip(
                            label: '柱状',
                            selected: chartType == 1,
                            color: accent,
                            icon: Icons.bar_chart_rounded,
                            onTap: () => setSt(() => chartType = 1),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 210,
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                      decoration: BoxDecoration(
                        color: AppColors.tint(accent, 0.06),
                        borderRadius: BorderRadius.circular(AppRadius.field),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.14)),
                      ),
                      child: chart,
                    ),
                    if (!compare) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _StatChip(
                            label: '平均',
                            value: '${_shortNumber(avg)}${metric.unit}',
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          _StatChip(
                            label: '最高',
                            value: '${_shortNumber(maxV)}${metric.unit}',
                            color: AppColors.mint,
                          ),
                          const SizedBox(width: 8),
                          _StatChip(
                            label: '最低',
                            value: '${_shortNumber(minV)}${metric.unit}',
                            color: AppColors.sky,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '共 ${points.length} 条记录 · 图里的横轴是打卡日期',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _metricTextOf(CheckInRecord r) {
    final parts = <String>[];
    r.metricValues.forEach((id, v) {
      final m = widget.project.findMetric(id);
      if (m == null) return;
      parts.add('${m.name} $v${m.unit}');
    });
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;

    final today = DateTime.now();
    final todayRequired = p.isRequiredOn(today);
    final todayReachedLimit = p.reachedLimitOn(today);
    final showCheckInBtn = todayRequired && !todayReachedLimit;

    final selectedRecords =
        _selectedDay == null ? <CheckInRecord>[] : p.recordsOn(_selectedDay!);

    final monthCount = p.records
        .where((r) => r.time.year == _month.year && r.time.month == _month.month)
        .length;

    final screenW = MediaQuery.of(context).size.width;
    double scale = screenW / 1000;
    if (scale < 1.0) scale = 1.0;
    if (scale > 2.0) scale = 2.0;

    final bigBtnH = (screenW * 0.08).clamp(60.0, 180.0);
    final smallBtnD = (screenW * 0.12).clamp(60.0, 220.0);
    final gap = 16.0 * scale;

    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bigBtnH + 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 10),
                child: Row(
                  children: [
                    _MonthArrow(
                      icon: Icons.chevron_left,
                      onTap: () => setState(() {
                        _month = DateTime(_month.year, _month.month - 1);
                      }),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${_month.year}年${_month.month}月',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '本月打卡 $monthCount 次 · 连续 ${p.currentStreak(today)} 天',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MonthArrow(
                      icon: Icons.chevron_right,
                      onTap: () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1);
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const Row(
              children: [
                _WeekLabel('一'),
                _WeekLabel('二'),
                _WeekLabel('三'),
                _WeekLabel('四'),
                _WeekLabel('五'),
                _WeekLabel('六'),
                _WeekLabel('日'),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: (firstWeekday - 1) + daysInMonth,
              itemBuilder: (ctx, i) {
                if (i < firstWeekday - 1) return const SizedBox();
                final dayNum = i - (firstWeekday - 1) + 1;
                final day = DateTime(_month.year, _month.month, dayNum);
                final color = _dayColor(day);
                final isSelected =
                    _selectedDay != null && _sameDay(day, _selectedDay!);
                final isToday = _sameDay(day, today);
                final filled = color != null;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = day),
                  child: Container(
                    margin: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: filled ? color : null,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: AppColors.ink, width: 2)
                          : (isToday
                              ? Border.all(
                                  color: AppColors.pink, width: 2)
                              : null),
                    ),
                    child: Center(
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1,
                          color: filled ? Colors.white : AppColors.inkSoft,
                          fontWeight:
                              filled ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedDay == null
                                ? '点击日期查看详情'
                                : '${_selectedDay!.year}年${_selectedDay!.month}月${_selectedDay!.day}日',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (selectedRecords.isNotEmpty)
                          Pill(
                            text: '${selectedRecords.length} 次',
                            color: AppColors.mint,
                            dense: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedRecords.isEmpty)
                      const Row(
                        children: [
                          Icon(
                            Icons.local_florist_rounded,
                            size: 16,
                            color: AppColors.inkSoft,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '这天没有打卡记录',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      )
                    else
                      ...selectedRecords.map(_recordTile),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, gap, 16, gap),
          child: Row(
            children: [
              if (showCheckInBtn) ...[
                _CircleButton(
                  diameter: smallBtnD,
                  icon: Icons.bar_chart,
                  label: '统计',
                  onTap: _showStatsDialog,
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _PillButton(
                    height: bigBtnH,
                    icon: Icons.check_rounded,
                    label: '打卡',
                    onTap: () => _checkInDialog(DateTime.now()),
                  ),
                ),
                SizedBox(width: gap),
                _CircleButton(
                  diameter: smallBtnD,
                  icon: Icons.edit_calendar,
                  label: '补打卡',
                  onTap: _pickDateAndCheckIn,
                ),
              ] else ...[
                Expanded(
                  child: _PillButton(
                    height: bigBtnH,
                    icon: Icons.bar_chart_rounded,
                    label: '统计',
                    onTap: _showStatsDialog,
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _PillButton(
                    height: bigBtnH,
                    icon: Icons.edit_calendar_rounded,
                    label: '补打卡',
                    onTap: _pickDateAndCheckIn,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _WeekLabel extends StatelessWidget {
  final String text;
  const _WeekLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final double diameter;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({
    required this.diameter,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = diameter * 0.30;
    final fontSize = diameter * 0.135;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: AppShadow.soft(AppColors.pink, opacity: 0.20),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: AppColors.pink),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final double height;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillButton({
    required this.height,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.42;
    final fontSize = height * 0.28;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pink, AppColors.grape],
        ),
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: AppShadow.soft(AppColors.pink, opacity: 0.35),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(height / 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize, color: Colors.white),
                SizedBox(width: height * 0.15),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _chartPadding = EdgeInsets.fromLTRB(40, 14, 12, 26);

/// 统计弹窗里那种圆角胶囊筛选标签
class _ChartChip extends StatelessWidget {
  const _ChartChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? color : AppColors.line,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: selected ? Colors.white : color,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图表下面的「平均 / 最高 / 最低」小方块
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.tint(color, 0.12),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图表里的小工具：把数值压成短一点的写法
String _shortNumber(double v) {
  final s = v.toStringAsFixed(v.abs() >= 100 ? 0 : 1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

void _paintLabel(
  Canvas canvas,
  String text,
  Offset at, {
  Color color = AppColors.inkSoft,
  double size = 9,
  FontWeight weight = FontWeight.w600,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}

void _paintDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
  const dash = 4.0;
  const gap = 5.0;
  final total = (to - from).distance;
  if (total <= 0) return;
  final dir = (to - from) / total;
  var placed = 0.0;
  while (placed < total) {
    final end = (placed + dash).clamp(0.0, total);
    canvas.drawLine(from + dir * placed, from + dir * end, paint);
    placed += dash + gap;
  }
}

/// 把折线拉成平滑曲线，视觉上比纯折线柔和
Path _smoothPath(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) return path;
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i];
    final p1 = pts[i + 1];
    final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.unit,
    required this.color,
  });

  final List<MapEntry<DateTime, double>> points;
  final String unit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartW = size.width - _chartPadding.left - _chartPadding.right;
    final chartH = size.height - _chartPadding.top - _chartPadding.bottom;
    if (chartW <= 0 || chartH <= 0) return;

    var minV = points.first.value;
    var maxV = points.first.value;
    for (final p in points) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    var span = maxV - minV;
    if (span.abs() < 1e-9) {
      span = maxV.abs() < 1 ? 1 : maxV.abs() * 0.2;
    }
    final pad = span * 0.18;
    final yMin = minV - pad;
    final yMax = maxV + pad;
    final yRange = yMax - yMin;

    // 虚线网格 + 纵轴数值
    final gridPaint = Paint()
      ..color = AppColors.inkSoft.withValues(alpha: 0.20)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = _chartPadding.top + chartH * i / 3;
      _paintDashedLine(
        canvas,
        Offset(_chartPadding.left, y),
        Offset(_chartPadding.left + chartW, y),
        gridPaint,
      );
      _paintLabel(
        canvas,
        _shortNumber(yMax - yRange * i / 3),
        Offset(0, y - 5),
      );
    }

    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? _chartPadding.left + chartW / 2
          : _chartPadding.left + chartW * i / (points.length - 1);
      final y = _chartPadding.top +
          chartH -
          ((points[i].value - yMin) / yRange) * chartH;
      offsets.add(Offset(x, y));
    }

    final linePath = _smoothPath(offsets);

    // 曲线下面的渐变填充
    final fill = Path.from(linePath)
      ..lineTo(offsets.last.dx, _chartPadding.top + chartH)
      ..lineTo(offsets.first.dx, _chartPadding.top + chartH)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(
          Rect.fromLTWH(_chartPadding.left, _chartPadding.top, chartW, chartH),
        ),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 数据点：白心彩圈，最后一个点实心大一点
    for (var i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final isLast = i == offsets.length - 1;
      canvas.drawCircle(o, isLast ? 4.6 : 3.4, Paint()..color = color);
      if (!isLast) {
        canvas.drawCircle(o, 3.4, Paint()..color = Colors.white);
        canvas.drawCircle(
          o,
          3.4,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // 最后一个点的数值（唯一带单位标注的位置，避免图里到处是字）
    _paintLabel(
      canvas,
      '${_shortNumber(points.last.value)}$unit',
      Offset(
        (offsets.last.dx - 22).clamp(0.0, size.width - 44),
        (offsets.last.dy - 16).clamp(0.0, size.height),
      ),
      color: color,
      size: 10,
      weight: FontWeight.w800,
    );

    // 横轴日期
    final step = (points.length / 4).ceil().clamp(1, 999);
    for (var i = 0; i < points.length; i += step) {
      final t = points[i].key;
      _paintLabel(
        canvas,
        '${t.month}/${t.day}',
        Offset(
          (offsets[i].dx - 12).clamp(0.0, size.width - 24),
          _chartPadding.top + chartH + 6,
        ),
      );
    }
    final lastDay = points.last.key;
    _paintLabel(
      canvas,
      '${lastDay.month}/${lastDay.day}',
      Offset(
        (offsets.last.dx - 12).clamp(0.0, size.width - 24),
        _chartPadding.top + chartH + 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.points,
    required this.unit,
    required this.color,
  });

  final List<MapEntry<DateTime, double>> points;
  final String unit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartW = size.width - _chartPadding.left - _chartPadding.right;
    final chartH = size.height - _chartPadding.top - _chartPadding.bottom;
    if (chartW <= 0 || chartH <= 0) return;

    var minV = points.first.value;
    var maxV = points.first.value;
    for (final p in points) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    var span = maxV - minV;
    if (span.abs() < 1e-9) span = maxV.abs() < 1 ? 1 : maxV.abs() * 0.4;
    final base = minV - span * 0.25;
    final top = maxV + span * 0.12;
    final range = (top - base) == 0 ? 1.0 : (top - base);

    final gridPaint = Paint()
      ..color = AppColors.inkSoft.withValues(alpha: 0.20)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = _chartPadding.top + chartH * i / 3;
      _paintDashedLine(
        canvas,
        Offset(_chartPadding.left, y),
        Offset(_chartPadding.left + chartW, y),
        gridPaint,
      );
      _paintLabel(
        canvas,
        _shortNumber(top - range * i / 3),
        Offset(0, y - 5),
      );
    }

    final slotW = chartW / points.length;
    final barW = (slotW * 0.56).clamp(5.0, 26.0);
    final showValues = points.length <= 8;

    for (var i = 0; i < points.length; i++) {
      final h = ((points[i].value - base) / range) * chartH;
      final cx = _chartPadding.left + slotW * i + slotW / 2;
      final rect = Rect.fromLTWH(
        cx - barW / 2,
        _chartPadding.top + chartH - h,
        barW,
        h,
      );
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.45)],
          ).createShader(rect),
      );
      if (showValues) {
        _paintLabel(
          canvas,
          _shortNumber(points[i].value),
          Offset(cx - 12, rect.top - 13),
          color: color,
          size: 9.5,
          weight: FontWeight.w800,
        );
      }
    }

    // 基线
    canvas.drawLine(
      Offset(_chartPadding.left, _chartPadding.top + chartH),
      Offset(_chartPadding.left + chartW, _chartPadding.top + chartH),
      Paint()
        ..color = AppColors.inkSoft.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );

    final step = (points.length / 4).ceil().clamp(1, 999);
    for (var i = 0; i < points.length; i += step) {
      final t = points[i].key;
      final cx = _chartPadding.left + slotW * i + slotW / 2;
      _paintLabel(
        canvas,
        '${t.month}/${t.day}',
        Offset((cx - 12).clamp(0.0, size.width - 24), _chartPadding.top + chartH + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

/// 图表区没有数据时的占位
class _ChartEmptyHint extends StatelessWidget {
  const _ChartEmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '这个时间段还没有数据',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}
