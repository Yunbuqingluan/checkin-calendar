import 'package:flutter/material.dart';

/// 一条对比曲线：某个指标的全部数据点
class CompareSeries {
  const CompareSeries({
    required this.name,
    required this.unit,
    required this.color,
    required this.points,
  });

  final String name;
  final String unit;
  final Color color;
  final List<MapEntry<DateTime, double>> points;
}

/// 多指标对比折线：每个指标各自归一化后叠在同一张图上，只用来比较趋势，
/// 所以纵轴不标具体数值（不同指标量纲不同，标了会误导）。
class CompareChartPainter extends CustomPainter {
  CompareChartPainter({required this.series});

  final List<CompareSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 8.0;
    const right = 8.0;
    const bottom = 22.0;
    final chartW = size.width - left - right;
    final chartH = size.height - top - bottom;
    if (chartW <= 0 || chartH <= 0) return;

    final dates = <DateTime>{};
    for (final s in series) {
      for (final p in s.points) {
        dates.add(DateTime(p.key.year, p.key.month, p.key.day));
      }
    }
    if (dates.isEmpty) return;
    final sorted = dates.toList()..sort();

    double xOf(DateTime d) {
      if (sorted.length == 1) return left + chartW / 2;
      final i = sorted.indexWhere(
          (e) => e.year == d.year && e.month == d.month && e.day == d.day);
      return left + chartW * (i < 0 ? 0 : i) / (sorted.length - 1);
    }

    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + chartH * i / 3;
      canvas.drawLine(Offset(left, y), Offset(left + chartW, y), grid);
    }

    for (final s in series) {
      var minV = s.points.first.value;
      var maxV = s.points.first.value;
      for (final p in s.points) {
        if (p.value < minV) minV = p.value;
        if (p.value > maxV) maxV = p.value;
      }

      double yOf(double v) {
        if ((maxV - minV).abs() < 1e-9) return top + chartH / 2;
        return top + chartH * (1 - (v - minV) / (maxV - minV));
      }

      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      var started = false;
      for (final p in s.points) {
        final off = Offset(
          xOf(DateTime(p.key.year, p.key.month, p.key.day)),
          yOf(p.value),
        );
        if (started) {
          path.lineTo(off.dx, off.dy);
        } else {
          path.moveTo(off.dx, off.dy);
          started = true;
        }
      }
      canvas.drawPath(path, line);

      final dot = Paint()..color = s.color;
      for (final p in s.points) {
        canvas.drawCircle(
          Offset(
            xOf(DateTime(p.key.year, p.key.month, p.key.day)),
            yOf(p.value),
          ),
          2.5,
          dot,
        );
      }
    }

    final step = (sorted.length / 5).ceil();
    for (var i = 0; i < sorted.length; i += step) {
      final d = sorted[i];
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.month}/${d.day}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xOf(d) - tp.width / 2, top + chartH + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CompareChartPainter oldDelegate) =>
      oldDelegate.series != series;
}
