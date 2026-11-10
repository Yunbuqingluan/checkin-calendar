import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'app_theme.dart';
import 'models.dart';
import 'storage.dart';
import 'notification_service.dart';
import 'project_detail_page.dart';
import 'project_icon.dart';
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

  /// 本次启动是否已经提示过通知权限，避免反复弹
  bool _askedNotificationPermission = false;

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
    _checkNotificationPermission();
    if (!widget.enableOnboarding) {
      if (widget.alwaysShowGuide) _startCoachGuide();
      return;
    }
    if (widget.alwaysShowGuide || await OnboardingFlag.shouldShow()) {
      _startCoachGuide();
    }
  }

  /// 有项目开着提醒，但系统没给通知权限时提示一次
  Future<void> _checkNotificationPermission() async {
    if (_askedNotificationPermission) return;
    if (!NotificationService.supported) return;
    final reminders = _projects.where((p) => p.reminderOn).length;
    if (reminders == 0) return;
    _askedNotificationPermission = true;
    final allowed = await NotificationService.hasPermission();
    if (allowed || !mounted) return;
    await _showPermissionDialog(reminders);
  }

  Future<void> _showPermissionDialog(int reminders) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            boxShadow: AppShadow.lift,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBubble(
                    size: 38,
                    color: AppColors.tint(AppColors.mango, 0.28),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      size: 19,
                      color: AppColors.mango,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '提醒可能收不到',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '有 $reminders 个项目开了打卡提醒，但系统还没允许这个应用发通知，'
                '到点不会有提醒。',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, 'later'),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.creamDeep,
                        foregroundColor: AppColors.inkSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      child: const Text('稍后再说'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'open'),
                      child: const Text('去开启'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action != 'open') return;

    final granted = await NotificationService.requestPermission();
    if (granted) {
      _showSnack('通知权限已开启，提醒会正常送达');
      await NotificationService.syncAll(_projects);
      return;
    }
    // 系统不给弹申请框（勾了不再询问）时，直接把人送到系统设置
    await NotificationService.openSettings();
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
        text: '点这里新建一个项目：起名字、选图标，设定隔多久打卡一次。',
        targetKey: _addKey,
      ),
      CoachStep(
        text: '项目多了用搜索：输入两个字，就能筛出想找的那一个。',
        targetKey: _searchKey,
      ),
      CoachStep(
        text: '左边的菜单里有今日待打卡、统计总览，还能批量导出全部项目、'
            '导入别处备份的文件。',
        targetKey: _menuKey,
      ),
    ];
    if (_projects.isNotEmpty) {
      steps.add(CoachStep(
        text: '点卡片进入详情，打卡、日历、统计都在里面；'
            '长按卡片可以编辑、拖拽排序、导出或删除。',
        targetKey: _firstCardKey,
      ));
    }
    steps.add(CoachStep(
      text: '设置里能切换深色/浅色、打开通知权限、更换数据目录，'
          '也能指定导出位置。',
      targetKey: _menuKey,
    ));
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

  Future<void> _openAddMenu() async {
    final box = _addKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      await _showProjectEditor();
      return;
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    const menuWidth = 172.0;
    var left = topLeft.dx + box.size.width - menuWidth;
    if (left < 8) left = 8;
    var top = topLeft.dy + box.size.height + 6;
    if (top > overlay.size.height - 150) top = topLeft.dy - 146;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - menuWidth,
        overlay.size.height - top - 8,
      ),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      items: [
        _addMenuItem(
          value: 'new',
          icon: Icons.add_rounded,
          color: AppColors.pink,
          title: '新建项目',
        ),
        _addMenuItem(
          value: 'import',
          icon: Icons.file_download_rounded,
          color: AppColors.sky,
          title: '导入项目',
          withDivider: true,
        ),
      ],
    );
    if (result == 'new') {
      await _showProjectEditor();
    } else if (result == 'import') {
      await _importProject();
    }
  }

  PopupMenuItem<String> _addMenuItem({
    required String value,
    required IconData icon,
    required Color color,
    required String title,
    bool withDivider = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          IconBubble(
            size: 30,
            color: AppColors.tint(color, 0.20),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importProject() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      allowMultiple: true,
    );
    final paths = [
      for (final f in result?.files ?? const [])
        if (f.path != null) f.path!,
    ];
    if (paths.isEmpty) return;

    var imported = 0;
    var images = 0;
    var failed = 0;
    final names = <String>[];
    for (final path in paths) {
      try {
        final outcomes = await Storage.importProjectsFromFile(path);
        for (final outcome in outcomes) {
          final p = outcome.project;
          p.imported = true;
          p.id =
              '${DateTime.now().millisecondsSinceEpoch}_${imported}_${_projects.length}';
          _projects.add(p);
          names.add(p.name);
          images += outcome.imageCount;
          imported++;
        }
      } on FormatException {
        failed++;
      } catch (e) {
        failed++;
      }
    }

    if (imported == 0) {
      _showSnack(
        failed > 1 ? '导入失败：这几个文件里都没有项目数据' : '导入失败：这个文件里没有项目数据',
      );
      return;
    }

    setState(() {});
    await _save();

    final buffer = StringBuffer();
    if (imported == 1) {
      buffer.write('已导入：${names.first}');
    } else {
      buffer.write('已导入 $imported 个项目');
    }
    if (images > 0) buffer.write('，含 $images 张图片');
    if (failed > 0) buffer.write('；$failed 个文件没读出来');
    _showSnack(buffer.toString());
  }

  Future<void> _exportAll() async {
    if (_projects.isEmpty) {
      _showSnack('还没有项目可以导出');
      return;
    }
    final result = await Storage.exportAllToPublic(_projects);
    final where = result.visible
        ? '已导出到 ${result.location}'
        : '已导出（应用目录）：${result.location}';
    _showSnack(
      result.imageCount > 0
          ? '$where，共 ${_projects.length} 个项目 · ${result.imageCount} 张图片'
          : '$where，共 ${_projects.length} 个项目',
    );
  }

  Future<void> _exportProject(Project p) async {
    final result = await Storage.exportProjectToPublic(p);
    final where = result.visible
        ? '已导出到 ${result.location}'
        : '已导出（应用目录）：${result.location}';
    _showSnack(
      result.imageCount > 0 ? '$where，含 ${result.imageCount} 张图片' : where,
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
    // 必填项没填时不要直接把弹窗关掉，留在原地提示
    String? nameError;
    String? formError;

    String? validate() {
      if (nameCtrl.text.trim().isEmpty) {
        nameError = '先给项目起个名字';
        return 'name';
      }
      if (freq == FrequencyType.weekly && weekly.isEmpty) {
        formError = '选一个星期几';
        return 'freq';
      }
      if (freq == FrequencyType.monthly && monthly.isEmpty) {
        formError = '选一个每月的日期';
        return 'freq';
      }
      if (freq == FrequencyType.interval) {
        final n = int.tryParse(intervalCtrl.text.trim()) ?? 0;
        if (n < 1) {
          formError = '间隔天数要填 1 或更大';
          return 'freq';
        }
      }
      if (limitType == 1) {
        final n = int.tryParse(limitCtrl.text.trim()) ?? 0;
        if (n < 1) {
          formError = '每天次数要填 1 或更大';
          return 'freq';
        }
      }
      return null;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final scheme = Theme.of(ctx).colorScheme;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.92,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        IconBubble(
                          size: 42,
                          color: AppColors.tint(AppColors.pink, 0.18),
                          child: Icon(
                            isEdit
                                ? Icons.edit_rounded
                                : Icons.auto_awesome_rounded,
                            size: 20,
                            color: AppColors.pink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEdit ? '编辑项目' : '新建项目',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isEdit ? '改完记得保存' : '起个名字，挑一个喜欢的图标',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) {
                              if (nameError != null) {
                                setSt(() => nameError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: '项目名称',
                              hintText: '比如：晨间阅读',
                              errorText: nameError,
                            ),
                          ),
                          _editorSection(
                            title: '选择图标',
                            hint: '不选就用默认图标',
                            child: _buildIconPicker(
                              current: iconPath,
                              onChanged: (v) {
                                // 换掉上传的图标时，把上一张复制进来的图片删掉
                                if (iconPath.startsWith('file://') &&
                                    iconPath != v) {
                                  unawaited(Storage.deleteImage(
                                      iconPath.substring(7)));
                                }
                                setSt(() => iconPath = v);
                              },
                              showCount: iconShowCount,
                              onMore: () => setSt(() {
                                iconShowCount += 5;
                                if (iconShowCount >
                                    Storage.presetIcons.length + 1) {
                                  iconShowCount = Storage.presetIcons.length + 1;
                                }
                              }),
                            ),
                          ),
                          _editorSection(
                            title: '打卡频率',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('每日'),
                                      selected: freq == FrequencyType.daily,
                                      onSelected: (_) => setSt(
                                          () => freq = FrequencyType.daily),
                                    ),
                                    ChoiceChip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('每隔 '),
                                          SizedBox(
                                            width: 32,
                                            child: TextField(
                                              controller: intervalCtrl,
                                              keyboardType:
                                                  TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                hintText: 'N',
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 4),
                                              ),
                                              enabled:
                                                  freq == FrequencyType.interval,
                                              onChanged: (_) => setSt(() =>
                                                  freq = FrequencyType.interval),
                                            ),
                                          ),
                                          const Text(' 天'),
                                        ],
                                      ),
                                      selected: freq == FrequencyType.interval,
                                      onSelected: (_) => setSt(
                                          () => freq = FrequencyType.interval),
                                    ),
                                    ChoiceChip(
                                      label: const Text('每周'),
                                      selected: freq == FrequencyType.weekly,
                                      onSelected: (_) => setSt(
                                          () => freq = FrequencyType.weekly),
                                    ),
                                    ChoiceChip(
                                      label: const Text('每月'),
                                      selected: freq == FrequencyType.monthly,
                                      onSelected: (_) => setSt(
                                          () => freq = FrequencyType.monthly),
                                    ),
                                  ],
                                ),
                                if (freq == FrequencyType.weekly)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: List.generate(7, (i) {
                                        final d = i + 1;
                                        const labels = [
                                          '一',
                                          '二',
                                          '三',
                                          '四',
                                          '五',
                                          '六',
                                          '日'
                                        ];
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
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
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
                              ],
                            ),
                          ),
                          _editorSection(
                            title: '每日打卡次数',
                            hint: '一天能打几次',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
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
                                        width: 32,
                                        child: TextField(
                                          controller: limitCtrl,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            hintText: 'N',
                                            contentPadding:
                                                EdgeInsets.symmetric(vertical: 4),
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
                          ),
                          _editorSection(
                            title: '数据指标',
                            hint: '可选，比如页数、公里',
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('添加'),
                              onPressed: () => setSt(() {
                                metrics.add(Metric(
                                  id: DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString(),
                                  name: '',
                                  unit: '',
                                ));
                              }),
                            ),
                            child: metrics.isEmpty
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '还没有指标，打卡时只记时间和备注',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: metrics.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final m = entry.value;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                initialValue: m.name,
                                                decoration: const InputDecoration(
                                                  labelText: '指标名称',
                                                  isDense: true,
                                                ),
                                                onChanged: (v) => m.name = v,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              width: 84,
                                              child: TextFormField(
                                                initialValue: m.unit,
                                                decoration: const InputDecoration(
                                                  labelText: '单位',
                                                  isDense: true,
                                                ),
                                                onChanged: (v) => m.unit = v,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.remove_circle_rounded,
                                                color: AppColors.coral,
                                              ),
                                              onPressed: () =>
                                                  setSt(() => metrics.removeAt(i)),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          _editorSection(
                            title: '提醒',
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                              decoration: BoxDecoration(
                                color: reminder
                                    ? AppColors.tint(AppColors.mango, 0.16)
                                    : AppColors.tint(AppColors.inkSoft, 0.06),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.field),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      IconBubble(
                                        size: 34,
                                        color: AppColors.tint(
                                            AppColors.mango, 0.35),
                                        child: Icon(
                                          Icons.notifications_active_rounded,
                                          size: 17,
                                          color: AppColors.mango,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '开启提醒',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              reminder
                                                  ? '每天 ${_fmtTime(reminderTime)} 提醒，已打卡自动跳过'
                                                  : '到点推送通知，提醒你完成打卡',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.inkSoft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch(
                                        value: reminder,
                                        onChanged: (v) async {
                                          setSt(() => reminder = v);
                                          if (!v) return;
                                          final granted = await NotificationService
                                              .requestPermission();
                                          if (!granted && ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    '通知权限未开启，提醒不会生效，可以到系统通知设置里手动打开'),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  if (reminder)
                                    GestureDetector(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: ctx,
                                          initialTime: reminderTime,
                                        );
                                        if (picked != null) {
                                          setSt(() => reminderTime = picked);
                                        }
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .surface
                                              .withValues(alpha: 0.7),
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.field - 4),
                                        ),
                                        child: Row(
                                          children: [
                                            const Text(
                                              '提醒时间',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _fmtTime(reminderTime),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.mango,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: AppColors.inkSoft,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (formError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: AppColors.coral,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    formError!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.coral,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: () {
                                  nameError = null;
                                  formError = null;
                                  if (validate() != null) {
                                    setSt(() {});
                                    return;
                                  }
                                  Navigator.pop(ctx, true);
                                },
                                child: Text(isEdit ? '保存' : '创建'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

  Widget _editorSection({
    required String title,
    String? hint,
    Widget? trailing,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
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

    Widget tile({
      required bool selected,
      required VoidCallback onTap,
      required Widget child,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.tint(AppColors.pink, 0.16)
                : AppColors.tint(AppColors.sky, 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.pink : AppColors.line,
              width: selected ? 2.4 : 1.2,
            ),
            boxShadow:
                selected ? AppShadow.soft(AppColors.pink, opacity: 0.30) : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: child,
                ),
                if (selected)
                  const Positioned(
                    right: 2,
                    bottom: 2,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: AppColors.pink,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        tile(
          selected: current.startsWith('file://'),
          onTap: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.image,
            );
            final path = res?.files.single.path;
            if (path != null) {
              // 相册里选的原图只是临时路径，复制一份进数据目录，清理缓存后图标才不会丢
              try {
                onChanged('file://${await Storage.saveImage(path)}');
              } catch (e) {
                debugPrint('保存图标失败：$e');
                onChanged('file://$path');
              }
            }
          },
          child: current.startsWith('file://')
              ? Image.file(
                  File(current.substring(7)),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_rounded,
                        size: 18, color: AppColors.inkSoft),
                    SizedBox(height: 2),
                    Text(
                      '上传',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
        ),
        for (int i = 0; i < displayCount - 1; i++)
          tile(
            selected: current == Storage.presetIcons[i],
            onTap: () => onChanged(Storage.presetIcons[i]),
            child: Image.asset(
              'assets/icons/${Storage.presetIcons[i]}',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 16),
            ),
          ),
        if (showMore)
          tile(
            selected: false,
            onTap: onMore,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.more_horiz_rounded, size: 20),
                SizedBox(height: 2),
                Text(
                  '更多',
                  style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft),
                ),
              ],
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
    final accent = AppColors.of(p.id);
    final result = await showActionSheet(
      context,
      title: p.name,
      subtitle: '${_freqText(p)} · ${_limitText(p)}',
      leading: IconBubble(
        size: 44,
        color: AppColors.tint(accent, 0.14),
        child: ProjectIcon(project: p, size: 32),
      ),
      actions: [
        ActionSheetItem(
          value: 'edit',
          label: '编辑项目',
          description: '名称、频率、提醒、图标',
          icon: Icons.tune_rounded,
          color: accent,
        ),
        ActionSheetItem(
          value: 'sort',
          label: '拖拽排序',
          description: '按住卡片上下拖动，调整显示顺序',
          icon: Icons.swap_vert_rounded,
          color: AppColors.sky,
        ),
        ActionSheetItem(
          value: 'export',
          label: '导出项目',
          description: '备注和图片一起打包成 zip',
          icon: Icons.ios_share_rounded,
          color: AppColors.grape,
        ),
        ActionSheetItem(
          value: 'delete',
          label: '删除项目',
          description: '记录和图片都会一起清掉',
          icon: Icons.delete_outline_rounded,
          color: AppColors.pink,
          danger: true,
        ),
      ],
    );

    if (result == null) return;

    if (result == 'delete') {
      final images = [
        for (final r in p.records) ...r.images,
        if (p.iconPath.startsWith('file://')) p.iconPath.substring(7),
      ];
      setState(() => _projects.removeWhere((e) => e.id == p.id));
      await _save();
      // 项目删掉之后，它名下的备注图片和上传的图标都没人用了
      await Storage.deleteImages(images);
    } else if (result == 'edit') {
      await _showProjectEditor(project: p);
    } else if (result == 'export') {
      await _exportProject(p);
    } else if (result == 'sort') {
      // 排序只能对完整列表做，先把搜索收起来
      _searchCtrl.clear();
      setState(() {
        _searching = false;
        _sorting = true;
      });
    }
  }

  Future<void> _openSettings() async {
    // 先把目录读取挂上，再立刻弹窗：不让磁盘 IO 挡住界面
    final pathFuture = Storage.dataFolderPath();
    final exportDir = ValueNotifier<String>('');
    Storage.loadExportDir().then((v) => exportDir.value = v);
    if (!mounted) return;
    await showDialog(
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
                Row(
                  children: [
                    const Text('导出位置',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _chooseExportDir(ctx, exportDir),
                      child: const Text('更改'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<String>(
                  valueListenable: exportDir,
                  builder: (ctx, custom, _) {
                    return SelectableText(
                      custom.isEmpty
                          ? '默认：下载/打卡日历导出/'
                          : '$custom/打卡日历导出/',
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
                const Text('打卡日历 v1.3.2\n本地打卡记录应用',
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
    exportDir.dispose();
  }

  /// 设置里的「更改导出位置」
  Future<void> _chooseExportDir(
    BuildContext dialogCtx,
    ValueNotifier<String> current,
  ) async {
    final choice = await showActionSheet(
      context,
      title: '导出位置',
      subtitle: current.value.isEmpty
          ? '现在用系统下载目录'
          : '${current.value}/打卡日历导出/',
      leading: IconBubble(
        size: 36,
        color: AppColors.tint(AppColors.sky, 0.22),
        child: const Icon(Icons.folder_rounded, size: 18, color: AppColors.sky),
      ),
      actions: [
        const ActionSheetItem(
          value: 'pick',
          label: '选择文件夹',
          icon: Icons.folder_open_rounded,
          color: AppColors.sky,
          description: '自己挑一个目录放导出的 zip',
        ),
        if (current.value.isNotEmpty)
          const ActionSheetItem(
            value: 'reset',
            label: '恢复默认位置',
            icon: Icons.restart_alt_rounded,
            color: AppColors.inkSoft,
            description: '回到系统下载目录',
          ),
      ],
    );

    if (choice == 'reset') {
      await Storage.saveExportDir('');
      current.value = '';
      _showSnack('导出位置已恢复默认');
      return;
    }
    if (choice != 'pick') return;

    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出位置',
      );
    } catch (e) {
      _showSnack('这台设备打不开文件夹选择器');
      return;
    }
    if (dir == null) return;

    if (!await Storage.canWriteTo(dir)) {
      _showSnack('这个文件夹写不进去，换一个试试（或者用默认位置）');
      return;
    }
    await Storage.saveExportDir(dir);
    current.value = dir;
    _showSnack('导出位置已改为 $dir/打卡日历导出/');
  }

  /// 频率文案，例如「每天」「每隔 2 天」「每周一三五」
  String _freqText(Project p) {
    switch (p.frequencyType) {
      case FrequencyType.daily:
        return '每天';
      case FrequencyType.interval:
        return '每隔 ${p.intervalDays < 1 ? 1 : p.intervalDays} 天';
      case FrequencyType.weekly:
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final days = [...p.weeklyDays]..sort();
        if (days.isEmpty) return '每周';
        return '每周${days.map((d) => names[(d - 1).clamp(0, 6)]).join()}';
      case FrequencyType.monthly:
        final days = [...p.monthlyDays]..sort();
        if (days.isEmpty) return '每月';
        return '每月 ${days.join('、')} 号';
    }
  }

  String _limitText(Project p) =>
      p.dailyLimit == -1 ? '不限次数' : '每天 ${p.dailyLimit} 次';

  Widget _buildCard(Project p, {bool draggable = false}) {
    final accent = AppColors.of(p.id);
    // 进度稍微调深一档，压在图上不糊，又不至于像纯黑那么硬
    final progress = AppColors.onImage(accent);
    final today = DateTime.now();
    final checkedToday = p.recordsOn(today).isNotEmpty;
    final doneToday = p.reachedLimitOn(today) ||
        (p.dailyLimit == -1 && checkedToday);
    final required = p.isRequiredOn(today);
    final streak = p.currentStreak(today);
    final weekDone = _weeklyDone(p);
    final weekTarget = _weeklyTarget(p);

    final statusText = !required
        ? '今天不用打卡'
        : (doneToday ? '今天已完成' : _todayStatus(p));
    // 状态文字跟其它信息同一个颜色，状态靠图标那一点点颜色区分
    final statusIconColor = !required
        ? AppColors.inkSoft
        : (doneToday ? AppColors.mint : AppColors.pink);

    return PressableScale(
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
      onLongPressStart:
          draggable ? null : (pos) => _onCardLongPress(p, pos),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          boxShadow: AppShadow.soft(accent, opacity: 0.20),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _cardImage(p, accent)),
            // 半透明白纱：压住图片的花色，保证上面的字还是能看清
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.76),
                      Colors.white.withValues(alpha: 0.46),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17.5,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                                shadows: [
                                  Shadow(color: Colors.white, blurRadius: 6),
                                  Shadow(color: Colors.white, blurRadius: 12),
                                ],
                              ),
                            ),
                          ),
                          if (p.imported) ...[
                            const SizedBox(width: 6),
                            const Pill(
                              text: '导入',
                              color: AppColors.mango,
                              dense: true,
                            ),
                          ],
                          if (p.reminderOn) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.notifications_active_rounded,
                              size: 14,
                              color: accent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_freqText(p)} · ${_limitText(p)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                          shadows: [
                            Shadow(color: Colors.white, blurRadius: 5),
                            Shadow(color: Colors.white, blurRadius: 9),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右上角是本周进度环，下面竖着排两张信息卡（从下往上：状态 → 连续天数）
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        shape: BoxShape.circle,
                      ),
                      child: MiniRing(
                        value: weekTarget == 0 ? 0 : weekDone / weekTarget,
                        size: 40,
                        stroke: 5,
                        color: progress,
                        child: Text(
                          '$weekDone/$weekTarget',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: progress,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (streak > 1) ...[
                      Pill(
                        text: '连续 $streak 天',
                        color: AppColors.onImage(AppColors.mango, 0.55),
                        background: AppColors.mango,
                        icon: Icons.local_fire_department_rounded,
                        dense: true,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Pill(
                      text: statusText,
                      color: AppColors.inkSoft,
                      iconColor: statusIconColor,
                      background: Colors.white.withValues(alpha: 0.86),
                      icon: !required
                          ? Icons.nightlight_round
                          : (doneToday
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded),
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            // 底部整行只放本周七天进度
            SizedBox(
              height: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: _WeekBar(
                        project: p,
                        color: progress,
                        dayOffset: i,
                      ),
                    ),
                  ],
                ],
              ),
            ),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片背景用项目自己的图片，没有就退回同色系渐变
  Widget _cardImage(Project p, Color accent) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.tint(accent, 0.55),
            AppColors.tint(accent, 0.18),
          ],
        ),
      ),
    );
    if (p.iconPath.isEmpty) return fallback;
    if (p.iconPath.startsWith('file://')) {
      return Image.file(
        File(p.iconPath.substring(7)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Image.asset(
      'assets/icons/${Storage.iconAsset(p.iconPath)}',
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.pink, AppColors.grape],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: AppShadow.soft(AppColors.grape, opacity: 0.28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.event_available_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          '打卡日历',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _drawerStat('${_projects.length}', '个项目'),
                        const SizedBox(width: 8),
                        _drawerStat('$pending', '待打卡'),
                        const SizedBox(width: 8),
                        _drawerStat('$doneToday', '已完成'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _drawerTile(
                      icon: Icons.checklist_rounded,
                      label: '全部项目',
                      color: AppColors.sky,
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
                    _drawerTile(
                      icon: Icons.today_rounded,
                      label: '今日待打卡',
                      color: AppColors.mango,
                      badge: pending,
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
                    _drawerTile(
                      icon: Icons.insights_rounded,
                      label: '统计总览',
                      color: AppColors.mint,
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
                    _drawerTile(
                      icon: Icons.save_alt_rounded,
                      label: '批量导出',
                      color: AppColors.coral,
                      badge: _projects.length,
                      onTap: () {
                        Navigator.pop(context);
                        _exportAll();
                      },
                    ),
                    _drawerTile(
                      icon: Icons.file_download_rounded,
                      label: '导入项目',
                      color: AppColors.leaf,
                      onTap: () {
                        Navigator.pop(context);
                        _importProject();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      child: Divider(color: scheme.outlineVariant, height: 1),
                    ),
                    _drawerTile(
                      icon: Icons.settings_rounded,
                      label: '设置',
                      color: AppColors.grape,
                      onTap: () {
                        Navigator.pop(context);
                        _openSettings();
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    '所有数据只保存在本机',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerStat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    int? badge,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        tileColor: selected ? color.withValues(alpha: 0.14) : null,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            // 选中态用加深的同色系，浅蓝色直接放白底上会看不清
            color: selected ? AppColors.onImage(color, 0.35) : null,
          ),
        ),
        trailing: (badge == null || badge == 0)
            ? null
            : Pill(
                text: '$badge',
                color: Colors.white,
                background: AppColors.berry,
                dense: true,
              ),
        onTap: onTap,
      ),
    );
  }

  /// 顶部问候区：日期 + 今天还剩几项 + 今日完成环
  Widget _buildHeader() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
    final required = _projects.where((p) => p.isRequiredOn(today)).toList();
    final done = required.where((p) => p.reachedLimitOn(today)).length;
    final pending = required.length - done;
    final progress = required.isEmpty ? 0.0 : done / required.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '打卡日历',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${now.month} 月 ${now.day} 日 · 周${weekNames[now.weekday - 1]}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  required.isEmpty
                      ? '今天没有需要打卡的项目'
                      : (pending == 0 ? '今天的任务都完成啦' : '今天还有 $pending 项没打卡'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: required.isEmpty
                        ? AppColors.inkSoft
                        : (pending == 0 ? AppColors.mint : AppColors.pink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MiniRing(
            value: progress,
            size: 58,
            stroke: 7,
            color: AppColors.pink,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$done',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.pink,
                  ),
                ),
                Text(
                  '/${required.length}',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  setState(() {
                    _searching = false;
                    _searchCtrl.clear();
                  });
                },
              )
            : _sorting
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _sorting = false),
                  )
                : Builder(
                    builder: (ctx) => IconButton(
                      key: _menuKey,
                      icon: const Icon(Icons.menu_rounded),
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
                icon: const Icon(Icons.search_rounded),
                onPressed: () => setState(() => _searching = true),
              ),
            if (!_searching)
              IconButton(
                key: _addKey,
                onPressed: _openAddMenu,
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.pink, AppColors.grape],
                    ),
                    boxShadow:
                        AppShadow.soft(AppColors.pink, opacity: 0.35),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ],
      ),
      drawer: _sorting ? null : _buildDrawer(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(
                          icon: Icons.emoji_objects_outlined,
                          title: '还没有打卡项目',
                          subtitle: '新建一个习惯，今天就开始记录',
                          action: FilledButton.icon(
                            onPressed: () => _showProjectEditor(),
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('新建第一个项目'),
                          ),
                        )
                      : _sorting
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                              itemCount: filtered.length,
                              // 默认的长按拖拽（500ms）太不灵敏，改成按下即拖
                              buildDefaultDragHandles: false,
                              onReorderStart: (_) =>
                                  HapticFeedback.mediumImpact(),
                              onReorderEnd: (_) =>
                                  HapticFeedback.selectionClick(),
                              onReorderItem: (oldIndex, newIndex) {
                                if (newIndex < 0 || newIndex >= _projects.length) {
                                  return;
                                }
                                setState(() {
                                  final item = _projects.removeAt(oldIndex);
                                  _projects.insert(newIndex, item);
                                });
                                // 顺序也是数据的一部分，拖完立刻落盘
                                _save();
                              },
                              itemBuilder: (ctx, i) {
                                final p = filtered[i];
                                return Padding(
                                  key: ValueKey(p.id),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: ReorderableDragStartListener(
                                    index: i,
                                    child: AspectRatio(
                                      aspectRatio: _cardAspect,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child:
                                                _buildCard(p, draggable: true),
                                          ),
                                          const SizedBox(width: 6),
                                          _SortGrip(accent: AppColors.of(p.id)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 1,
                                mainAxisSpacing: 14,
                                childAspectRatio: _cardAspect,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                return KeyedSubtree(
                                  key: i == 0 ? _firstCardKey : null,
                                  child: _buildCard(filtered[i]),
                                );
                              },
                            ),
                ),
              ],
            ),
    );

    return scaffold;
  }
}

/// 本周七天的小进度条：打卡过就是实心，该打卡没打是浅色，不用打卡留白。
class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.project,
    required this.color,
    required this.dayOffset,
  });

  final Project project;

  /// 已经调深过的强调色，保证压在图片上也看得清
  final Color color;
  final int dayOffset;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final day = DateTime(monday.year, monday.month, monday.day + dayOffset);
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final required = project.isRequiredOn(day);
    final checked = project.isCheckedOn(day);

    final barColor = checked
        ? color
        : required
            ? color.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.7);

    return Container(
      height: isToday ? 11 : 7,
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: isToday
            ? Border.all(color: color, width: 1.4)
            : (checked || required
                ? null
                : Border.all(
                    color: color.withValues(alpha: 0.28), width: 1)),
      ),
    );
  }
}

/// 排序模式下卡片右侧的抓手：按住这里（或整张卡）都能直接拖
class _SortGrip extends StatelessWidget {
  const _SortGrip({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: AppShadow.soft(accent, opacity: 0.16),
      ),
      child: Center(
        child: Icon(
          Icons.drag_indicator_rounded,
          size: 18,
          color: accent,
        ),
      ),
    );
  }
}

/// 卡片宽高比：网格和排序列表共用，进出排序时卡片不会跳高度
const double _cardAspect = 2.36;
