import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

class SpendingChart extends StatefulWidget {
  final List<DailyPoint> points;
  final bool hidden;
  const SpendingChart({super.key, required this.points, required this.hidden});
  @override
  State<SpendingChart> createState() => _SpendingChartState();
}

class _SpendingChartState extends State<SpendingChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant SpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: Text('Spending chart hidden', style: TextStyle(color: muted)),
        ),
      );
    }
    if (widget.points.isEmpty || widget.points.every((p) => p.amount == 0)) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: Text(
            'Add an expense to see your daily pattern.',
            style: TextStyle(color: muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final selected = _selected == null ? null : widget.points[_selected!];
    return Column(
      children: [
        SizedBox(
          height: 30,
          child: Text(
            selected == null
                ? 'Touch the chart to explore each day'
                : '${selected.label}  ·  ${money(selected.amount, false)}',
            style: TextStyle(
              color: selected == null ? muted : ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            void select(Offset position) {
              final ratio =
                  ((position.dx - 48) / math.max(1, constraints.maxWidth - 60))
                      .clamp(0.0, 1.0);
              setState(
                () => _selected = (ratio * (widget.points.length - 1)).round(),
              );
            }

            return Semantics(
              label: 'Daily spending chart. Touch or drag to inspect daily amounts.',
              child: GestureDetector(
                onTapDown: (details) => select(details.localPosition),
                onHorizontalDragUpdate: (details) =>
                    select(details.localPosition),
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _ChartPainter(widget.points, _selected),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<DailyPoint> points;
  final int? selected;
  _ChartPainter(this.points, this.selected);
  static const purple = Color(0xFF8B5CF6);
  void label(
    Canvas canvas,
    String text,
    Offset position, {
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'TrackerSans',
          fontSize: 10,
          color: muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position - Offset(center ? painter.width / 2 : 0, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(48, 12, size.width - 12, size.height - 28);
    final maxValue =
        points.fold<double>(0, (max, p) => math.max(max, p.amount)) * 1.15;
    final grid = Paint()
      ..color = const Color(0xFFEAEFF5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final amount = maxValue * i / 3;
      label(
        canvas,
        amount >= 100000
            ? '${(amount / 100000).toStringAsFixed(1)}L'
            : amount >= 1000
            ? '${(amount / 1000).toStringAsFixed(1)}k'
            : amount.toStringAsFixed(0),
        Offset(0, y - 6),
      );
    }
    Offset point(int index) => Offset(
      chart.left + chart.width * index / math.max(1, points.length - 1),
      chart.bottom - points[index].amount / maxValue * chart.height,
    );
    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(chart.right, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            purple.withValues(alpha: 0.22),
            purple.withValues(alpha: 0.01),
          ],
        ).createShader(chart),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = purple
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final index in {0, points.length ~/ 2, points.length - 1}) {
      label(
        canvas,
        points[index].label,
        Offset(point(index).dx, chart.bottom + 10),
        center: true,
      );
    }
    if (selected != null) {
      final p = point(selected!);
      canvas.drawLine(
        Offset(p.dx, chart.top),
        Offset(p.dx, chart.bottom),
        Paint()
          ..color = purple.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 5, Paint()..color = purple);
      canvas.drawCircle(p, 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.selected != selected;
}
