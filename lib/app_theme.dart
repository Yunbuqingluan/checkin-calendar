import 'package:flutter/material.dart';

/// 配色：奶油底色 + 糖果色点缀，圆角大、阴影软。
class AppColors {
  const AppColors._();

  static const cream = Color(0xFFFFF9F3);
  static const creamDeep = Color(0xFFF6EDE3);
  static const ink = Color(0xFF3D3546);
  static const inkSoft = Color(0xFF9A8FA6);
  static const line = Color(0xFFF1E7DC);

  static const pink = Color(0xFFFF7FA2);
  static const coral = Color(0xFFFF9B7A);
  static const mango = Color(0xFFFFBE5C);
  static const mint = Color(0xFF57D3A6);
  static const sky = Color(0xFF63C7F0);
  static const grape = Color(0xFFAE8CF5);
  static const berry = Color(0xFFF26D9B);
  static const leaf = Color(0xFF9BD770);

  /// 项目卡片的备选色，按项目 id 取模，保证同一个项目每次都是同一种颜色。
  static const palette = <Color>[
    pink,
    mint,
    sky,
    mango,
    grape,
    coral,
    leaf,
    berry,
  ];

  static Color of(String id) =>
      palette[id.hashCode.abs() % palette.length];

  /// 浅色底：把主色稀释成卡片背景
  static Color tint(Color c, [double alpha = 0.16]) =>
      Color.alphaBlend(c.withValues(alpha: alpha), Colors.white);

  static Color deepTint(Color c, [double alpha = 0.28]) =>
      Color.alphaBlend(c.withValues(alpha: alpha), Colors.white);

  /// 压在图片上的强调色：往深了调一点点，和图片的花色拉开对比又不至于发黑
  static Color onImage(Color c, [double amount = 0.32]) =>
      Color.lerp(c, const Color(0xFF221C2B), amount)!;
}

class AppRadius {
  const AppRadius._();

  static const card = 28.0;
  static const bubble = 20.0;
  static const field = 22.0;
  static const sheet = 34.0;
  static const pill = 999.0;
}

class AppShadow {
  const AppShadow._();

  /// 带颜色的柔和投影，比纯黑阴影更“软”
  static List<BoxShadow> soft(Color accent, {double opacity = 0.22}) => [
        BoxShadow(
          color: accent.withValues(alpha: opacity),
          blurRadius: 22,
          offset: const Offset(0, 10),
          spreadRadius: -6,
        ),
      ];

  static const List<BoxShadow> lift = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 24,
      offset: Offset(0, 12),
      spreadRadius: -8,
    ),
  ];
}

/// 统一造主题：亮色 / 暗色都用同一套圆角和组件样式。
ThemeData buildAppTheme({
  required Color seed,
  required Brightness brightness,
  String? fontFamily,
}) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final scheme = base.copyWith(
    primary: dark ? base.primary : seed,
    surface: dark ? const Color(0xFF221F2A) : Colors.white,
    surfaceContainerHighest:
        dark ? const Color(0xFF2C2836) : AppColors.creamDeep,
    onSurface: dark ? const Color(0xFFF3EEF7) : AppColors.ink,
    outline: dark ? const Color(0xFF6F6880) : AppColors.inkSoft,
    outlineVariant: dark ? const Color(0xFF3A3546) : AppColors.line,
  );

  final textTheme = Typography.material2021(colorScheme: scheme)
      .black
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamily: fontFamily,
      )
      .copyWith(
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: scheme.onSurface,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      )
      .apply(fontFamily: fontFamily);

  final stadium = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.pill),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF17151C) : AppColors.cream,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(size: 24, color: scheme.onSurface),
      actionsIconTheme: IconThemeData(size: 26, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(AppRadius.sheet),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: textTheme.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF3A3546) : AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: stadium,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        highlightColor: seed.withValues(alpha: 0.12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF2C2836) : AppColors.creamDeep,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: TextStyle(color: scheme.outline, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: seed.withValues(alpha: 0.6), width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      backgroundColor: dark ? const Color(0xFF2C2836) : Colors.white,
      selectedColor: seed.withValues(alpha: 0.18),
      // 颜色写死跟着明暗走：以前继承主题，浅色模式下 label 会变成白色看不见
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: dark ? Colors.white : AppColors.ink,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: dark ? Colors.white : AppColors.onImage(seed, 0.25),
      ),
      side: BorderSide(color: scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.bubble),
      ),
      iconColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: seed,
      foregroundColor: Colors.white,
      elevation: 6,
      highlightElevation: 4,
      shape: stadium,
      extendedTextStyle:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: seed,
      linearTrackColor: seed.withValues(alpha: 0.14),
      circularTrackColor: seed.withValues(alpha: 0.14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : scheme.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? seed
            : scheme.outlineVariant,
      ),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: AppColors.berry,
      textColor: Colors.white,
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

/// 按下会轻微缩小的容器，给卡片一点“弹”的手感。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onLongPressStart;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // 没有长按回调时不要注册长按手势：否则它会抢走 ReorderableListView
    // 拖动所需的那次长按，表现就是「按住卡片怎么拖都不动」
    final wantsLongPress =
        widget.onLongPress != null || widget.onLongPressStart != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onLongPressStart: wantsLongPress
          ? (d) => widget.onLongPressStart?.call(d.globalPosition)
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 圆角卡片：白底、细边、柔和投影，可选主题色。
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.radius = AppRadius.card,
    this.shadowColor,
    this.onTap,
    this.onLongPress,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final Color? shadowColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ?? scheme.surface;

    final box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
        boxShadow: dark ? null : AppShadow.soft(shadowColor ?? Colors.black12),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null && onLongPress == null) return box;
    return PressableScale(onTap: onTap, onLongPress: onLongPress, child: box);
  }
}

/// 圆形/圆角图标底座，用来放项目图标。
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.child,
    this.size = 56,
    this.color,
    this.radius,
  });

  final Widget child;
  final double size;
  final Color? color;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius ?? size * 0.36),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: child),
    );
  }
}

/// 小圆角标签。
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.color = AppColors.inkSoft,
    this.background,
    this.icon,
    this.iconColor,
    this.dense = false,
  });

  final String text;
  final Color color;
  final Color? background;
  final IconData? icon;

  /// 图标单独上色：文字保持信息色，状态靠图标区分
  final Color? iconColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: iconColor ?? color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: dense ? 11 : 12,
              fontWeight: dense ? FontWeight.w600 : FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区标题：左侧小色点 + 标题，右侧可选操作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.color,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 12),
  });

  final String title;
  final Color? color;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态：大图标 + 两行文案 + 可选按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: scheme.outline),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 圆形进度：给首页卡片上的“本周完成”用。
class MiniRing extends StatelessWidget {
  const MiniRing({
    super.key,
    required this.value,
    this.size = 44,
    this.color,
    this.stroke = 5,
    this.child,
  });

  final double value;
  final double size;
  final Color? color;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: accent.withValues(alpha: 0.16),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          child ??
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
        ],
      ),
    );
  }
}

/// 长按卡片弹出的操作面板：一个圆角浮起的小卡片，比系统菜单柔和得多。
class ActionSheetItem {
  const ActionSheetItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.description,
    this.danger = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String? description;
  final bool danger;
}

Future<String?> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  required List<ActionSheetItem> actions,
}) {
  // 弹在屏幕正中间，用缩放 + 淡入，比从底部滑上来干净
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x55241C2E),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.sheet),
                      boxShadow: AppShadow.lift,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (leading != null) ...[
                              leading,
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      height: 1.15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final a in actions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ActionRow(
                              item: a,
                              onTap: () => Navigator.pop(ctx, a.value),
                            ),
                          ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.creamDeep,
                              foregroundColor: AppColors.inkSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              '取消',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.item, required this.onTap});

  final ActionSheetItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = item.danger
        ? AppColors.pink.withValues(alpha: 0.10)
        : AppColors.tint(item.color, 0.12);
    final fg = item.danger ? AppColors.pink : item.color;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          child: Row(
            children: [
              IconBubble(
                size: 34,
                color: Colors.white,
                child: Icon(item.icon, size: 17, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: item.danger ? AppColors.pink : AppColors.ink,
                      ),
                    ),
                    if (item.description != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        item.description!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: fg.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
