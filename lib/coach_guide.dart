import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// 是否已经看过新手引导（键名沿用旧版，老用户不会被重复打扰）
class OnboardingFlag {
  static const _key = 'onboarding_done_v1';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_key) ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// 一步引导：箭头指向 [targetKey] 对应的按钮，气泡里说清楚它是干什么的
class CoachStep {
  const CoachStep({required this.text, required this.targetKey});

  final String text;
  final GlobalKey targetKey;
}

/// 盖在界面上的一层引导：挖空高亮 + 箭头 + 说明气泡。
///
/// 不改动被引导的界面本身，只根据 [CoachStep.targetKey] 找到控件位置来画。
class CoachGuide extends StatefulWidget {
  const CoachGuide({
    super.key,
    required this.steps,
    required this.index,
    required this.onNext,
    required this.onSkip,
  });

  final List<CoachStep> steps;
  final int index;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<CoachGuide> createState() => _CoachGuideState();
}

class _CoachGuideState extends State<CoachGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 目标控件在引导层坐标系里的位置
  Rect? _targetRect(BuildContext context) {
    final targetContext = widget.steps[widget.index].targetKey.currentContext;
    if (targetContext == null) return null;

    final box = targetContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;

    final self = context.findRenderObject();
    final origin = self is RenderBox ? self.localToGlobal(Offset.zero) : Offset.zero;
    return box.localToGlobal(Offset.zero) - origin & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final target = _targetRect(context);
    final isLast = widget.index == widget.steps.length - 1;

    // 气泡和箭头之间的留白
    const gap = 64.0;
    // 目标下方空间够就放下面，否则放上面
    final canBelow = target != null && size.height - target.bottom - 24 > 210;
    final below = target != null &&
        (canBelow || target.center.dy < size.height * 0.35);
    final bubble = _buildBubble(context, isLast);

    // 箭头竖直指向目标中点，气泡贴着目标放，看起来才不飘
    Offset? arrowFrom;
    Offset? arrowTo;
    if (target != null) {
      final x = target.center.dx.clamp(48.0, size.width - 48);
      if (below) {
        arrowTo = Offset(x, target.bottom + 12);
        arrowFrom = Offset(x, target.bottom + gap - 6);
      } else {
        arrowTo = Offset(x, target.top - 12);
        arrowFrom = Offset(x, target.top - gap + 6);
      }
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onNext,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _CoachPainter(
                    target: target,
                    pulse: _pulse.value,
                    highlight: Theme.of(context).colorScheme.primary,
                    arrowFrom: arrowFrom,
                    arrowTo: arrowTo,
                  ),
                ),
              ),
            ),
          ),
          if (target == null)
            Center(child: bubble)
          else if (below)
            Positioned(
              left: 20,
              right: 20,
              top: math.min(target.bottom + gap, size.height - 210),
              child: bubble,
            )
          else
            Positioned(
              left: 20,
              right: 20,
              bottom: math.min(size.height - target.top + gap, size.height - 210),
              child: bubble,
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, bool isLast) {
    final theme = Theme.of(context);
    final step = widget.steps[widget.index];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.pink.withValues(alpha: 0.28)),
        boxShadow: AppShadow.soft(AppColors.grape, opacity: 0.30),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.pink, AppColors.grape],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.index + 1}/${widget.steps.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onSkip,
                child: const Text('跳过'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: widget.onNext,
                child: Text(isLast ? '开始使用' : '下一步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({
    required this.target,
    required this.pulse,
    required this.highlight,
    this.arrowFrom,
    this.arrowTo,
  });

  final Rect? target;
  final double pulse;
  final Color highlight;
  final Offset? arrowFrom;
  final Offset? arrowTo;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;

    if (target == null) {
      canvas.drawRect(full, Paint()..color = Colors.black.withValues(alpha: 0.6));
      return;
    }

    final hole = RRect.fromRectAndRadius(
      target!.inflate(8),
      const Radius.circular(16),
    );

    // 半透明遮罩挖出一个洞
    final scrim = Path()..addRect(full);
    final cut = Path()..addRRect(hole);
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, cut),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    // 高亮描边 + 呼吸圈
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = highlight,
    );
    final breathe = 6 + pulse * 14;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        target!.inflate(8 + breathe),
        Radius.circular(18 + breathe),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = highlight.withValues(alpha: 0.35 * (1 - pulse)),
    );

    final from = arrowFrom;
    final to = arrowTo;
    if (from == null || to == null) return;
    _paintArrow(canvas, from, to, highlight);
  }

  /// 画一根带箭头的指示线
  void _paintArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final delta = to - from;
    if (delta.distance < 1) return;
    final dir = delta / delta.distance;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 线身（末端留出箭头长度）
    final shaftEnd = to - dir * 15;
    canvas.drawLine(from, shaftEnd, paint);

    // 箭头两条边
    final wingAngle = math.pi / 7;
    final left = _rotate(dir, wingAngle) * 16;
    final right = _rotate(dir, -wingAngle) * 16;
    canvas.drawLine(to, to - left, paint);
    canvas.drawLine(to, to - right, paint);
  }

  Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  @override
  bool shouldRepaint(covariant _CoachPainter old) =>
      old.target != target || old.pulse != pulse || old.arrowTo != arrowTo;
}
