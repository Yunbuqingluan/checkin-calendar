import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  Color? _dayColor(DateTime day) {
    final p = widget.project;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    final start = DateTime(p.createdAt.year, p.createdAt.month, p.createdAt.day);
    if (d.isBefore(start)) return null;
    if (p.isCheckedOn(d)) return p.isMakeUpOn(d) ? Colors.amber : Colors.green;
    if (p.isRequiredOn(d)) {
      if (d.isBefore(today)) return Colors.red;
      if (_sameDay(d, today)) return Colors.grey;
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
      if (f.path != null) {
        final saved = await Storage.saveImage(f.path!);
        newPaths.add(saved);
      }
    }
    return newPaths;
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
    final now = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(editRecord != null
              ? '编辑打卡'
              : (isMakeUp ? '补打卡' : '打卡')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (editRecord == null && !isMakeUp)
                    Text(
                      '时间：${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} '
                      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                    )
                  else if (editRecord == null && isMakeUp)
                    Text(
                      '日期：${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: '备注（可选）'),
                    maxLines: 2,
                  ),
                  if (widget.project.metrics.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('数据指标',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...widget.project.metrics.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: metricCtrls[m.id],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  '${m.name}${m.unit.isNotEmpty ? ' (${m.unit})' : ''}',
                            ),
                          ),
                        )),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('图片',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                        label: const Text('添加图片'),
                        onPressed: () async {
                          final res = await _pickImages(images);
                          setSt(() => images = res);
                        },
                      ),
                    ],
                  ),
                  if (images.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: images.map((path) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(path),
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => setSt(() => images.remove(path)),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
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
        ),
      ),
    );

    if (ok != true) return;

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
      final actualTime = isMakeUp
          ? DateTime(day.year, day.month, day.day, now.hour, now.minute)
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
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, day),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      child: Center(child: Text('$dayNum')),
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
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (result == null) return;
    if (result == 'edit') {
      await _checkInDialog(r.time, editRecord: r);
    } else if (result == 'delete') {
      setState(() => widget.project.records.remove(r));
    }
  }

  void _showImage(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.file(File(path)),
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final metric = widget.project.metrics[metricIndex];
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

          return AlertDialog(
            title: Text('${metric.name} 统计'),
            content: SizedBox(
              width: 520,
              height: 400,
              child: Column(
                children: [
                  if (widget.project.metrics.length > 1)
                    Wrap(
                      spacing: 6,
                      children: widget.project.metrics
                          .asMap()
                          .entries
                          .map((e) => ChoiceChip(
                                label: Text(e.value.name),
                                selected: metricIndex == e.key,
                                onSelected: (_) =>
                                    setSt(() => metricIndex = e.key),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (int i = 0; i < 4; i++)
                        ChoiceChip(
                          label: Text(['全部', '7 天', '30 天', '本月'][i]),
                          selected: timeRange == i,
                          onSelected: (_) => setSt(() => timeRange = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('折线'),
                        selected: chartType == 0,
                        onSelected: (_) => setSt(() => chartType = 0),
                      ),
                      ChoiceChip(
                        label: const Text('柱状'),
                        selected: chartType == 1,
                        onSelected: (_) => setSt(() => chartType = 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: points.isEmpty
                        ? const Center(child: Text('这个时间段还没有数据'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return CustomPaint(
                                size: Size(constraints.maxWidth,
                                    constraints.maxHeight),
                                painter: chartType == 0
                                    ? _LineChartPainter(
                                        points: points,
                                        unit: metric.unit,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary,
                                      )
                                    : _BarChartPainter(
                                        points: points,
                                        unit: metric.unit,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary,
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
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

    final screenW = MediaQuery.of(context).size.width;
    double scale = screenW / 1000;
    if (scale < 1.0) scale = 1.0;
    if (scale > 2.0) scale = 2.0;

    final bigBtnW = (screenW * 0.30).clamp(200.0, 700.0);
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _month = DateTime(_month.year, _month.month - 1);
                    }),
                  ),
                  Text('${_month.year}年${_month.month}月',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                      _month = DateTime(_month.year, _month.month + 1);
                    }),
                  ),
                ],
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
              padding: const EdgeInsets.all(8),
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
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = day),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: color?.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: Colors.teal, width: 2)
                          : (isToday
                              ? Border.all(color: Colors.teal.shade200)
                              : null),
                    ),
                    child: Center(
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          color: color == null ? null : Colors.white,
                          fontWeight: color == null
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDay == null
                        ? '点击日期查看详情'
                        : '${_selectedDay!.year}年${_selectedDay!.month}月${_selectedDay!.day}日',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (selectedRecords.isEmpty)
                    const Text('这天没有打卡记录',
                        style: TextStyle(color: Colors.grey))
                  else
                    ...selectedRecords.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTapDown: (details) {
                              _lastLongPressPos = details.globalPosition;
                            },
                            onLongPress: () {
                              _onRecordLongPress(
                                r,
                                _lastLongPressPos ?? Offset.zero,
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        r.isMakeUp
                                            ? Icons.edit_calendar
                                            : Icons.check_circle,
                                        color: r.isMakeUp
                                            ? Colors.amber
                                            : Colors.green,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        r.isMakeUp
                                            ? '补打卡'
                                            : '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  if (r.note.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(r.note),
                                  ],
                                  if (_metricTextOf(r).isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _metricTextOf(r),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                  if (r.images.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: r.images
                                          .map((path) => GestureDetector(
                                                onTap: () =>
                                                    _showImage(path),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.file(
                                                    File(path),
                                                    width: 70,
                                                    height: 70,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, _, _) =>
                                                            Container(
                                                      width: 70,
                                                      height: 70,
                                                      color: Colors
                                                          .grey.shade300,
                                                      child: const Icon(Icons
                                                          .broken_image),
                                                    ),
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: gap),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showCheckInBtn) ...[
                _CircleButton(
                  diameter: smallBtnD,
                  icon: Icons.bar_chart,
                  label: '统计',
                  onTap: _showStatsDialog,
                ),
                SizedBox(width: gap),
                _PillButton(
                  width: bigBtnW,
                  height: bigBtnH,
                  icon: Icons.check,
                  label: '打卡',
                  onTap: () => _checkInDialog(DateTime.now()),
                ),
                SizedBox(width: gap),
                _CircleButton(
                  diameter: smallBtnD,
                  icon: Icons.edit_calendar,
                  label: '补打卡',
                  onTap: _pickDateAndCheckIn,
                ),
              ] else ...[
                _PillButton(
                  width: bigBtnW,
                  height: bigBtnH,
                  icon: Icons.bar_chart,
                  label: '统计',
                  onTap: _showStatsDialog,
                ),
                SizedBox(width: gap),
                _PillButton(
                  width: bigBtnW,
                  height: bigBtnH,
                  icon: Icons.edit_calendar,
                  label: '补打卡',
                  onTap: _pickDateAndCheckIn,
                ),
              ],
            ],
          ),
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
        child: Text(text, style: const TextStyle(color: Colors.grey)),
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
    final color = Theme.of(context).colorScheme.primaryContainer;
    final fg = Theme.of(context).colorScheme.onPrimaryContainer;
    final iconSize = diameter * 0.32;
    final fontSize = diameter * 0.15;

    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: fg),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(fontSize: fontSize, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final double width;
  final double height;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillButton({
    required this.width,
    required this.height,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final fg = Theme.of(context).colorScheme.onPrimary;
    final iconSize = height * 0.45;
    final fontSize = height * 0.30;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: fg),
              SizedBox(width: height * 0.15),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: fg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _chartPadding = EdgeInsets.fromLTRB(44, 16, 16, 36);

class _LineChartPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> points;
  final String unit;
  final Color color;

  _LineChartPainter({
    required this.points,
    required this.unit,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartW = size.width - _chartPadding.left - _chartPadding.right;
    final chartH = size.height - _chartPadding.top - _chartPadding.bottom;
    if (chartW <= 0 || chartH <= 0) return;

    final minV = points.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final maxV = points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final padding = (maxV - minV) * 0.1;
    final yMin = minV - padding;
    final yMax = maxV + padding;
    final range = (yMax - yMin) == 0 ? 1.0 : (yMax - yMin);

    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(_chartPadding.left, _chartPadding.top),
      Offset(_chartPadding.left, _chartPadding.top + chartH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_chartPadding.left, _chartPadding.top + chartH),
      Offset(_chartPadding.left + chartW, _chartPadding.top + chartH),
      axisPaint,
    );

    for (int i = 0; i <= 4; i++) {
      final v = yMin + range * i / 4;
      final y = _chartPadding.top + chartH - chartH * i / 4;
      final tp = TextPainter(
        text: TextSpan(
          text: v.toStringAsFixed(1),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
          canvas, Offset(_chartPadding.left - tp.width - 4, y - tp.height / 2));
      canvas.drawLine(
        Offset(_chartPadding.left, y),
        Offset(_chartPadding.left + chartW, y),
        Paint()..color = Colors.grey.shade200,
      );
    }

    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? _chartPadding.left + chartW / 2
          : _chartPadding.left + chartW * i / (points.length - 1);
      final y = _chartPadding.top +
          chartH -
          ((points[i].value - yMin) / range) * chartH;
      offsets.add(Offset(x, y));
    }

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      path.lineTo(offsets[i].dx, offsets[i].dy);
    }
    canvas.drawPath(path, linePaint);

    for (final o in offsets) {
      canvas.drawCircle(o, 3, Paint()..color = color);
    }

    final step = (points.length / 6).ceil();
    for (int i = 0; i < points.length; i += step) {
      final t = points[i].key;
      final label = '${t.month}/${t.day}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas,
          Offset(offsets[i].dx - tp.width / 2, _chartPadding.top + chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _BarChartPainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> points;
  final String unit;
  final Color color;

  _BarChartPainter({
    required this.points,
    required this.unit,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartW = size.width - _chartPadding.left - _chartPadding.right;
    final chartH = size.height - _chartPadding.top - _chartPadding.bottom;
    if (chartW <= 0 || chartH <= 0) return;

    final values = points.map((e) => e.value).toList();
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final base = minV - (maxV - minV) * 0.2;
    final range = (maxV - base) == 0 ? 1.0 : (maxV - base);

    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final barPaint = Paint()..color = color;

    canvas.drawLine(
      Offset(_chartPadding.left, _chartPadding.top),
      Offset(_chartPadding.left, _chartPadding.top + chartH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_chartPadding.left, _chartPadding.top + chartH),
      Offset(_chartPadding.left + chartW, _chartPadding.top + chartH),
      axisPaint,
    );

    for (int i = 0; i <= 4; i++) {
      final v = base + range * i / 4;
      final y = _chartPadding.top + chartH - chartH * i / 4;
      final tp = TextPainter(
        text: TextSpan(
          text: v.toStringAsFixed(1),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(
          canvas, Offset(_chartPadding.left - tp.width - 4, y - tp.height / 2));
      canvas.drawLine(
        Offset(_chartPadding.left, y),
        Offset(_chartPadding.left + chartW, y),
        Paint()..color = Colors.grey.shade200,
      );
    }

    final slotW = chartW / points.length;
    final barW = slotW * 0.6;
    final offsets = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final h = ((points[i].value - base) / range) * chartH;
      final cx = _chartPadding.left + slotW * i + slotW / 2;
      final left = cx - barW / 2;
      final top = _chartPadding.top + chartH - h;
      final rect = Rect.fromLTWH(left, top, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        barPaint,
      );
      offsets.add(Offset(cx, _chartPadding.top + chartH));
    }

    final step = (points.length / 6).ceil();
    for (int i = 0; i < points.length; i += step) {
      final t = points[i].key;
      final label = '${t.month}/${t.day}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas,
          Offset(offsets[i].dx - tp.width / 2, _chartPadding.top + chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}