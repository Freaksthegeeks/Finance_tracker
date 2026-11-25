import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

class SpendingChart extends StatelessWidget {
  final List<DailyPoint> points;
  final bool hidden;
  final int? today;
  const SpendingChart({
    super.key,
    required this.points,
    required this.hidden,
    this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (points.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No spending to chart')),
      );
    }
    final maxAmount = points.fold<double>(
      0,
      (max, point) => math.max(max, point.amount),
    );
    return Semantics(
      label: hidden
          ? 'Daily spending chart. Amounts hidden.'
          : 'Daily spending chart. ${points.map((point) => '${point.label}: ${money(point.amount, false)}').join('; ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            maxY: maxAmount > 0 ? maxAmount * 1.15 : 1,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxAmount > 0 ? maxAmount / 3 : .25,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: colors.outlineVariant),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final day = value.toInt() + 1;
                    if (![1, 8, 15, 22, points.length].contains(day)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('$day', style: theme.textTheme.bodySmall),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var index = 0; index < points.length; index++)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: points[index].amount,
                      width: 6,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      color: index + 1 == today
                          ? colors.primary
                          : colors.outline,
                    ),
                  ],
                ),
            ],
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => colors.surface,
                tooltipBorder: BorderSide(color: colors.outlineVariant),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${points[groupIndex].label}\n',
                      theme.textTheme.labelLarge!,
                      textAlign: TextAlign.left,
                      children: [
                        TextSpan(
                          text: '■ ',
                          style: TextStyle(color: colors.primary),
                        ),
                        TextSpan(
                          text: 'Spent  ',
                          style: theme.textTheme.bodySmall,
                        ),
                        TextSpan(
                          text: money(rod.toY, hidden),
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryDonut extends StatelessWidget {
  final List<MapEntry<String, double>> slices;
  final bool hidden;
  final String caption;
  final ValueChanged<int> onSelect;
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.hidden,
    required this.caption,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    final chart = SizedBox(
      width: 154,
      height: 154,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 54,
              sectionsSpace: 3,
              sections: [
                for (final slice in slices)
                  PieChartSectionData(
                    value: slice.value,
                    color: categoryColor(context, slice.key),
                    showTitle: false,
                    radius: 19,
                  ),
              ],
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final index =
                      response?.touchedSection?.touchedSectionIndex ?? -1;
                  if (event is FlTapUpEvent &&
                      index >= 0 &&
                      index < slices.length) {
                    onSelect(index);
                  }
                },
              ),
            ),
          ),
          IgnorePointer(
            child: SizedBox(
              width: 102,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      money(total, hidden),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    caption,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final legend = Column(
      children: [
        for (var index = 0; index < slices.length; index++)
          InkWell(
            onTap: () => onSelect(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    color: categoryColor(context, slices[index].key),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slices[index].key,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(100 * slices[index].value / total).round()}%',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 280
          ? Column(children: [chart, legend])
          : Row(
              children: [
                chart,
                const SizedBox(width: 12),
                Expanded(child: legend),
              ],
            ),
    );
  }
}
