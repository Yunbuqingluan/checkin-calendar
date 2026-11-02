import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models.dart';
import 'storage.dart';
import 'notification_service.dart';
import 'project_detail_page.dart';
import 'coach_guide.dart';
import 'overview_page.dart';
import 'today_page.dart';
import 'main.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialProjects,
    this.enableOnboarding = true,
    this.alwaysShowGuide = false,
  });

  /// 直接指定项目列表并跳过本地读取，预览和测试里用
  final List<Project>? initialProjects;

  /// 是否显示首次进入的引导
  final bool enableOnboarding;

  /// 忽略「已看过」标记，强制显示引导
  final bool alwaysShowGuide;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Project> _projects = [];
  bool _loading = true;
  bool _searching = false;
  bool _sorting = false;
  final TextEditingController _searchCtrl = TextEditingController();

  // 引导要指的位置
  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey _firstCardKey = GlobalKey();

  int _coachStep = 0;
  OverlayEntry? _coachEntry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _coachEntry?.remove();
    _coachEntry = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = widget.initialProjects ?? await Storage.loadProjects();
    setState(() {
      _projects = list;
      _loading = false;
    });
    if (!widget.enableOnboarding) {
      if (widget.alwaysShowGuide) _startCoachGuide();
      return;
    }
    if (widget.alwaysShowGuide || await OnboardingFlag.shouldShow()) {
      _startCoachGuide();
    }
  }

  /// 从第一步开始，逐条箭头指向界面上的按钮
  void _startCoachGuide() {
    if (!mounted) return;
    // 等界面画完，按钮的位置才量得准
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _coachStep = 0;
      _showCoachEntry();
    });
  }

  void _showCoachEntry() {
    _coachEntry?.remove();
    final entry = OverlayEntry(builder: (_) => _buildCoachGuide());
    _coachEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Widget _buildCoachGuide() {
    final steps = _coachSteps();
    return CoachGuide(
      steps: steps,
      index: _coachStep.clamp(0, steps.length - 1),
      onNext: _nextCoachStep,
      onSkip: _finishCoachGuide,
    );
  }

  void _nextCoachStep() {
    final total = _coachSteps().length;
    if (_coachStep + 1 >= total) {
      _finishCoachGuide();
    } else {
      setState(() => _coachStep++);
      _coachEntry?.markNeedsBuild();
    }
  }

  Future<void> _finishCoachGuide() async {
    _coachEntry?.remove();
    _coachEntry = null;
    await OnboardingFlag.markDone();
  }

  List<CoachStep> _coachSteps() {
    final steps = <CoachStep>[
      CoachStep(
        text: '点这里新建一个项目：给它起名字、选图标，设定多久打卡一次。',
        targetKey: _addKey,
      ),
      CoachStep(
        text: '项目多了用搜索，输入两个字就能筛出想找的那个。',
        targetKey: _searchKey,
      ),
      CoachStep(
        text: '左边的菜单里有「今日待打卡」「统计总览」和设置，随时能回来查看。',
        targetKey: _menuKey,
      ),
    ];
    if (_projects.isNotEmpty) {
      steps.add(CoachStep(
        text: '点卡片进入详情：打卡、看日历和统计都在里面。',
        targetKey: _firstCardKey,
      ));
    }
    return steps;
  }

  Future<void> _save() async => await Storage.saveProjects(_projects);

  int _weeklyDone(Project p) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      if (day.isAfter(now)) break;
      if (p.isRequiredOn(day) && p.isCheckedOn(day)) count++;
    }
    return count;
  }

  int _weeklyTarget(Project p) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      if (p.isRequiredOn(day)) count++;
    }
    return count == 0 ? 7 : count;
  }

  String _todayStatus(Project p) {
    final today = DateTime.now();
    if (!p.isRequiredOn(today)) return '今日无需打卡';
    final records = p.recordsOn(today);
    if (p.dailyLimit == -1) return '今日已打卡：${records.length} 次';
    if (p.dailyLimit == 1) return records.isEmpty ? '未打卡' : '已打卡';
    return '已打卡：${records.length}/${p.dailyLimit}';
  }

  Future<void> _openNewProjectSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建项目'),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('导入项目'),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
          ],
        ),
      ),
    );

    if (result == 'new') {
      await _showProjectEditor();
    } else if (result == 'import') {
      await _importProject();
    }
  }

  Future<void> _importProject() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final content = await File(result.files.single.path!).readAsString();
      final p = Project.fromJson(jsonDecode(content));
      p.imported = true;
      p.id = DateTime.now().millisecondsSinceEpoch.toString();
      setState(() => _projects.add(p));
      await _save();
      _showSnack('已导入：${p.name}');
    } catch (e) {
      _showSnack('导入失败：文件格式不对');
    }
  }

  Future<void> _exportProject(Project p) async {
    final result = await Storage.exportProjectToPublic(p);
    _showSnack(
      result.visible ? '已导出到 ${result.location}' : '已导出（应用目录）：${result.location}',
    );
  }

  Future<void> _showProjectEditor({Project? project}) async {
    final isEdit = project != null;
    final nameCtrl = TextEditingController(text: project?.name ?? '');
    FrequencyType freq = project?.frequencyType ?? FrequencyType.daily;
    final intervalCtrl = TextEditingController(
        text: (project?.intervalDays ?? 2).toString());
    List<int> weekly = List.from(project?.weeklyDays ?? []);
    List<int> monthly = List.from(project?.monthlyDays ?? []);

    int limitType;
    if (project == null) {
      limitType = 0;
    } else if (project.dailyLimit == -1) {
      limitType = 2;
    } else if (project.dailyLimit == 1) {
      limitType = 0;
    } else {
      limitType = 1;
    }
    final limitCtrl = TextEditingController(
        text: (project != null && project.dailyLimit > 1)
            ? project.dailyLimit.toString()
            : '3');

    bool reminder = project?.reminderOn ?? false;
    TimeOfDay reminderTime = TimeOfDay(
      hour: (project?.reminderMinutes ?? 20 * 60) ~/ 60,
      minute: (project?.reminderMinutes ?? 20 * 60) % 60,
    );
    List<Metric> metrics = project?.metrics
            .map((m) => Metric(id: m.id, name: m.name, unit: m.unit))
            .toList() ??
        [];
    String iconPath = project?.iconPath ?? '';
    int iconShowCount = 4;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isEdit ? '编辑项目' : '新建项目'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '项目名称'),
                  ),
                  const SizedBox(height: 16),
                  const Text('选择图标'),
                  const SizedBox(height: 8),
                  _buildIconPicker(
                    current: iconPath,
                    onChanged: (v) => setSt(() => iconPath = v),
                    showCount: iconShowCount,
                    onMore: () => setSt(() {
                      iconShowCount += 4;
                      if (iconShowCount > Storage.presetIcons.length + 1) {
                        iconShowCount = Storage.presetIcons.length + 1;
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Text('打卡频率'),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('每日'),
                        selected: freq == FrequencyType.daily,
                        onSelected: (_) =>
                            setSt(() => freq = FrequencyType.daily),
                      ),
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('每隔 '),
                            SizedBox(
                              width: 36,
                              child: TextField(
                                controller: intervalCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'N',
                                ),
                                enabled: freq == FrequencyType.interval,
                                onChanged: (_) => setSt(
                                    () => freq = FrequencyType.interval),
                              ),
                            ),
                            const Text(' 天'),
                          ],
                        ),
                        selected: freq == FrequencyType.interval,
                        onSelected: (_) =>
                            setSt(() => freq = FrequencyType.interval),
                      ),
                      ChoiceChip(
                        label: const Text('每周'),
                        selected: freq == FrequencyType.weekly,
                        onSelected: (_) =>
                            setSt(() => freq = FrequencyType.weekly),
                      ),
                      ChoiceChip(
                        label: const Text('每月'),
                        selected: freq == FrequencyType.monthly,
                        onSelected: (_) =>
                            setSt(() => freq = FrequencyType.monthly),
                      ),
                    ],
                  ),
                  if (freq == FrequencyType.weekly)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        children: List.generate(7, (i) {
                          final d = i + 1;
                          final labels = ['一', '二', '三', '四', '五', '六', '日'];
                          return FilterChip(
                            label: Text('周${labels[i]}'),
                            selected: weekly.contains(d),
                            onSelected: (sel) => setSt(() {
                              if (sel) {
                                weekly.add(d);
                              } else {
                                weekly.remove(d);
                              }
                            }),
                          );
                        }),
                      ),
                    ),
                  if (freq == FrequencyType.monthly)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        children: List.generate(31, (i) {
                          final d = i + 1;
                          return FilterChip(
                            label: Text('$d'),
                            selected: monthly.contains(d),
                            onSelected: (sel) => setSt(() {
                              if (sel) {
                                monthly.add(d);
                              } else {
                                monthly.remove(d);
                              }
                            }),
                          );
                        }),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text('每日打卡次数'),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('1 次'),
                        selected: limitType == 0,
                        onSelected: (_) => setSt(() => limitType = 0),
                      ),
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 36,
                              child: TextField(
                                controller: limitCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'N',
                                ),
                                enabled: limitType == 1,
                                onChanged: (_) =>
                                    setSt(() => limitType = 1),
                              ),
                            ),
                            const Text(' 次'),
                          ],
                        ),
                        selected: limitType == 1,
                        onSelected: (_) => setSt(() => limitType = 1),
                      ),
                      ChoiceChip(
                        label: const Text('无上限'),
                        selected: limitType == 2,
                        onSelected: (_) => setSt(() => limitType = 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('数据指标'),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加'),
                        onPressed: () => setSt(() {
                          metrics.add(Metric(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            name: '',
                            unit: '',
                          ));
                        }),
                      ),
                    ],
                  ),
                  ...metrics.asMap().entries.map((entry) {
                    final i = entry.key;
                    final m = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: m.name,
                              decoration:
                                  const InputDecoration(labelText: '指标名称'),
                              onChanged: (v) => m.name = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              initialValue: m.unit,
                              decoration:
                                  const InputDecoration(labelText: '单位'),
                              onChanged: (v) => m.unit = v,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                            onPressed: () => setSt(() => metrics.removeAt(i)),
                          ),
                        ],
                      ),
                    );
                  }),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开启提醒'),
                    subtitle: Text(
                      reminder
                          ? '每天 ${_fmtTime(reminderTime)} 提醒，已打卡的日子自动跳过'
                          : '到点推送通知，提醒你完成打卡',
                    ),
                    value: reminder,
                    onChanged: (v) async {
                      setSt(() => reminder = v);
                      if (!v) return;
                      final granted =
                          await NotificationService.requestPermission();
                      if (!granted && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('通知权限未开启，提醒不会生效，可以到系统通知设置里手动打开'),
                          ),
                        );
                      }
                    },
                  ),
                  if (reminder)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('提醒时间'),
                      trailing: Text(
                        _fmtTime(reminderTime),
                        style: const TextStyle(fontSize: 16),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: reminderTime,
                        );
                        if (picked != null) setSt(() => reminderTime = picked);
                      },
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
              child: Text(isEdit ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (nameCtrl.text.trim().isEmpty) return;

    int finalLimit;
    if (limitType == 0) {
      finalLimit = 1;
    } else if (limitType == 2) {
      finalLimit = -1;
    } else {
      finalLimit = int.tryParse(limitCtrl.text) ?? 3;
      if (finalLimit < 1) finalLimit = 1;
    }

    metrics.removeWhere((m) => m.name.trim().isEmpty);

    if (isEdit) {
      setState(() {
        project.name = nameCtrl.text.trim();
        project.iconPath = iconPath;
        project.frequencyType = freq;
        project.intervalDays = int.tryParse(intervalCtrl.text) ?? 2;
        project.weeklyDays = weekly;
        project.monthlyDays = monthly;
        project.dailyLimit = finalLimit;
        project.reminderOn = reminder;
        project.reminderMinutes = reminderTime.hour * 60 + reminderTime.minute;
        project.metrics = metrics;
      });
    } else {
      final p = Project(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameCtrl.text.trim(),
        iconPath: iconPath,
        createdAt: DateTime.now(),
        frequencyType: freq,
        intervalDays: int.tryParse(intervalCtrl.text) ?? 2,
        weeklyDays: weekly,
        monthlyDays: monthly,
        dailyLimit: finalLimit,
        reminderOn: reminder,
        reminderMinutes: reminderTime.hour * 60 + reminderTime.minute,
        metrics: metrics,
      );
      setState(() => _projects.add(p));
    }
    await _save();
  }

  Widget _buildIconPicker({
    required String current,
    required ValueChanged<String> onChanged,
    required int showCount,
    required VoidCallback onMore,
  }) {
    final total = Storage.presetIcons.length + 1;
    final displayCount = showCount > total ? total : showCount;
    final showMore = displayCount < total;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        GestureDetector(
          onTap: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.image,
            );
            if (res != null && res.files.single.path != null) {
              onChanged('file://${res.files.single.path}');
            }
          },
          child: Container(
            width: 90,
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(
                color: current.startsWith('file://')
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                width: current.startsWith('file://') ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload, size: 16),
                  Text('上传', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
        for (int i = 0; i < displayCount - 1; i++)
          GestureDetector(
            onTap: () => onChanged(Storage.presetIcons[i]),
            child: Container(
              width: 90,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(
                  color: current == Storage.presetIcons[i]
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  width: current == Storage.presetIcons[i] ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                    'assets/icons/${Storage.presetIcons[i]}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, size: 16),
                  ),
                ),
              ),
            ),
          ),
        if (showMore)
          GestureDetector(
            onTap: onMore,
            child: Container(
              width: 90,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.more_horiz, size: 20),
                    Text('更多', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 长按卡片：在触点位置弹出菜单
  Future<void> _onCardLongPress(Project p, Offset globalPos) async {
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
        PopupMenuItem(value: 'sort', child: Text('排序')),
        PopupMenuItem(value: 'export', child: Text('导出')),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (result == null) return;

    if (result == 'delete') {
      setState(() => _projects.removeWhere((e) => e.id == p.id));
      await _save();
    } else if (result == 'edit') {
      await _showProjectEditor(project: p);
    } else if (result == 'export') {
      await _exportProject(p);
    } else if (result == 'sort') {
      setState(() => _sorting = true);
    }
  }

  Future<void> _openSettings() async {
    // 先把目录读取挂上，再立刻弹窗：不让磁盘 IO 挡住界面
    final pathFuture = Storage.dataFolderPath();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('主题色',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ValueListenableBuilder<Color>(
                  valueListenable: MyAppState.seedColor,
                  builder: (ctx, color, _) {
                    final colors = [
                      Colors.teal,
                      Colors.blue,
                      Colors.purple,
                      Colors.orange,
                      Colors.pink,
                      Colors.green,
                    ];
                    return Wrap(
                      spacing: 12,
                      children: colors.map((c) {
                        return GestureDetector(
                          onTap: () => MyAppState.seedColor.value = c,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: color == c
                                  ? Border.all(color: Colors.black, width: 2)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text('外观模式',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: MyAppState.themeMode,
                  builder: (ctx, mode, _) {
                    return Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('跟随系统'),
                          selected: mode == ThemeMode.system,
                          onSelected: (_) =>
                              MyAppState.themeMode.value = ThemeMode.system,
                        ),
                        ChoiceChip(
                          label: const Text('浅色'),
                          selected: mode == ThemeMode.light,
                          onSelected: (_) =>
                              MyAppState.themeMode.value = ThemeMode.light,
                        ),
                        ChoiceChip(
                          label: const Text('深色'),
                          selected: mode == ThemeMode.dark,
                          onSelected: (_) =>
                              MyAppState.themeMode.value = ThemeMode.dark,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('通知提醒',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => NotificationService.openSettings(),
                      child: const Text('系统通知设置'),
                    ),
                  ],
                ),
                const Text(
                  '在项目里打开「开启提醒」后，到设定时间会推送通知；'
                  '没收到通知多半是系统把通知权限关掉了，可以点上面的按钮去打开。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('数据目录',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final dir = await FilePicker.platform
                            .getDirectoryPath(dialogTitle: '选择新的数据目录');
                        if (dir == null) return;
                        try {
                          await Storage.changeDataDir(dir);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          _showSnack('数据目录已更改');
                        } catch (e) {
                          _showSnack('更改失败：$e');
                        }
                      },
                      child: const Text('更改'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FutureBuilder<String>(
                  future: pathFuture,
                  builder: (ctx, snapshot) {
                    final text = snapshot.connectionState != ConnectionState.done
                        ? '读取中…'
                        : (snapshot.data ?? '读取失败');
                    return SelectableText(
                      text,
                      style: const TextStyle(fontSize: 12),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startCoachGuide();
                    },
                    icon: const Icon(Icons.tips_and_updates, size: 18),
                    label: const Text('重新查看新手引导'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('关于',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('打卡日历 v1.2.0\n本地打卡记录应用',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBackground(Project p) {
    if (p.iconPath.isEmpty) {
      return Container(color: Colors.teal.shade100);
    }
    if (p.iconPath.startsWith('file://')) {
      final path = p.iconPath.substring(7);
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Container(color: Colors.teal.shade100),
      );
    }
    return Image.asset(
      'assets/icons/${Storage.iconAsset(p.iconPath)}',
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(color: Colors.teal.shade100),
    );
  }

  Widget _outlinedText(String text,
      {double fontSize = 16, FontWeight weight = FontWeight.normal}) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: weight,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.white,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: weight,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Project p, {bool draggable = false}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: draggable
            ? null
            : () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailPage(project: p),
                  ),
                );
                setState(() {});
                await _save();
              },
        onLongPressStart: draggable
            ? null
            : (details) => _onCardLongPress(p, details.globalPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCardBackground(p),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: _outlinedText(
                                p.name,
                                fontSize: 22,
                                weight: FontWeight.bold,
                              ),
                            ),
                            if (p.imported)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '由用户导入',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (p.reminderOn)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.alarm,
                              size: 18, color: Colors.black87),
                        ),
                      _outlinedText(
                        '${_weeklyDone(p)}/${_weeklyTarget(p)}',
                        fontSize: 18,
                        weight: FontWeight.w600,
                      ),
                    ],
                  ),
                  const Spacer(),
                  _outlinedText(_todayStatus(p), fontSize: 14),
                  if (p.metrics.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _outlinedText(
                      p.metrics
                          .map((m) {
                            final today = DateTime.now();
                            final recs = p.recordsOn(today);
                            if (recs.isEmpty) {
                              return '${m.name} --';
                            }
                            final last = recs.last;
                            final v = last.metricValues[m.id];
                            return '${m.name} ${v ?? '--'}${m.unit}';
                          })
                          .join('  ·  '),
                      fontSize: 12,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final pending = _projects
        .where((p) => p.isRequiredOn(today0) && !p.reachedLimitOn(today0))
        .length;
    final doneToday = _projects
        .where((p) => p.isRequiredOn(today0) && p.reachedLimitOn(today0))
        .length;
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_available, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        '打卡日历',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_projects.length} 个项目 · 今日待打卡 $pending 项',
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今日已完成 $doneToday 项',
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('全部项目'),
              selected: true,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _sorting = false;
                  _searching = false;
                  _searchCtrl.clear();
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('今日待打卡'),
              trailing: pending == 0 ? null : Badge(label: Text('$pending')),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TodayPage(projects: _projects),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('统计总览'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OverviewPage(projects: _projects),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '所有数据只保存在本机',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _projects.where((p) {
      if (_searchCtrl.text.isEmpty) return true;
      return p.name.contains(_searchCtrl.text);
    }).toList();

    final scaffold = Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索项目名称',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(_sorting ? '拖动排序' : ''),
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _searching = false;
                    _searchCtrl.clear();
                  });
                },
              )
            : _sorting
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _sorting = false),
                  )
                : Builder(
                    builder: (ctx) => IconButton(
                      key: _menuKey,
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
        actions: [
          if (_sorting)
            TextButton(
              onPressed: () async {
                setState(() => _sorting = false);
                await _save();
                _showSnack('排序已保存');
              },
              child: const Text('完成'),
            )
          else ...[
            if (!_searching)
              IconButton(
                key: _searchKey,
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _searching = true),
              ),
            if (!_searching)
              IconButton(
                key: _addKey,
                icon: const Icon(Icons.add_circle, size: 30),
                onPressed: _openNewProjectSheet,
              ),
          ],
        ],
      ),
      drawer: _sorting ? null : _buildDrawer(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? const Center(child: Text('还没有项目，点右上角 + 新建'))
              : _sorting
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = filtered.removeAt(oldIndex);
                          filtered.insert(newIndex, item);
                          _projects = filtered;
                        });
                      },
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        return Padding(
                          key: ValueKey(p.id),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            height: 160,
                            child: _buildCard(p, draggable: true),
                          ),
                        );
                      },
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 1,
                        mainAxisSpacing: 12,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        return KeyedSubtree(
                          key: i == 0 ? _firstCardKey : null,
                          child: _buildCard(filtered[i]),
                        );
                      },
                    ),
    );

    return scaffold;
  }
}