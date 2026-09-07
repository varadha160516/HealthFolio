import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';

class TrendsTab extends StatefulWidget {
  final String memberId;
  const TrendsTab({super.key, required this.memberId});
  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().api.getTrends(widget.memberId).then((d) {
      if (mounted) setState(() => _data = d);
    });
  }

  Color _dotColor(String? flag) {
    if (flag == 'out_of_range') return careloopDanger;
    if (flag == 'in_range') return careloopSuccess;
    return careloopMuted;
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const LoadingCenter();
    final grouped = (_data!['groupedByCategory'] as Map<String, dynamic>);
    final qualitative = (_data!['qualitativeTimelines'] as List<dynamic>);

    if (grouped.isEmpty && qualitative.isEmpty) {
      return const EmptyState(icon: Icons.show_chart_rounded, message: 'Not enough entries yet to chart — a second checkup for the same result will start the line.');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
      children: [
        for (final category in grouped.keys) ...[
          SectionCaption(category),
          for (final param in (grouped[category] as List<dynamic>)) _ParamChart(param: param, dotColor: _dotColor),
        ],
        if (qualitative.isNotEmpty) ...[
          const SectionCaption('Status timelines'),
          for (final param in qualitative) _QualitativeTimeline(param: param),
        ],
      ],
    );
  }
}

class _ParamChart extends StatelessWidget {
  final Map<String, dynamic> param;
  final Color Function(String?) dotColor;
  const _ParamChart({required this.param, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    final points = (param['points'] as List<dynamic>);
    final rangeType = param['range_type'];
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = points[i]['value'];
      if (v != null) spots.add(FlSpot(i.toDouble(), (v as num).toDouble()));
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final lastRange = points.last['resolved_reference_range'] as Map<String, dynamic>?;
    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final low = lastRange?['low'] != null ? (lastRange!['low'] as num).toDouble() : null;
    final high = lastRange?['high'] != null ? (lastRange!['high'] as num).toDouble() : null;
    // Extend the axis to always include the reference band, mirroring the web chart's
    // ifOverflow="extendDomain" fix — otherwise a tight auto-range clips the shaded band.
    if (low != null) minY = minY < low ? minY : low;
    if (high != null) maxY = maxY > high ? maxY : high;
    final pad = (maxY - minY).abs() * 0.15 + 0.5;
    minY -= pad;
    maxY += pad;

    // Design spec Section 3.6 — the line tells the same story as the ledger's flag column: clay
    // when the latest point is out of range, sage when in range, never a fixed brand color
    // regardless of status.
    final latestFlag = rangeType == 'interpretive_rule' ? null : points.last['in_range_flag'] as String?;
    final lineColor = latestFlag == 'out_of_range' ? careloopDanger : (latestFlag == 'in_range' ? careloopSuccess : careloopPrimary);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(param['display_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(param['unit'] ?? '', style: const TextStyle(color: careloopMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 38, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: careloopMuted)))),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox.shrink();
                        final date = (points[i]['test_date'] as String);
                        return Padding(padding: const EdgeInsets.only(top: 4), child: Text(date.length > 5 ? date.substring(5) : date, style: const TextStyle(fontSize: 9, color: careloopMuted)));
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: careloopBorder), left: BorderSide(color: careloopBorder))),
                extraLinesData: rangeType == 'fixed_range' && low != null && high != null
                    ? ExtraLinesData(horizontalLines: [
                        HorizontalLine(y: low, color: careloopSuccess.withValues(alpha: 0.4), strokeWidth: 1, dashArray: [4, 4]),
                        HorizontalLine(y: high, color: careloopSuccess.withValues(alpha: 0.4), strokeWidth: 1, dashArray: [4, 4]),
                      ])
                    : (rangeType == 'open_upper_bound' || rangeType == 'open_lower_bound') && low != null
                        ? ExtraLinesData(horizontalLines: [HorizontalLine(y: low, color: careloopWarning, strokeWidth: 1, dashArray: [4, 4])])
                        : null,
                rangeAnnotations: rangeType == 'fixed_range' && low != null && high != null
                    ? RangeAnnotations(horizontalRangeAnnotations: [HorizontalRangeAnnotation(y1: low, y2: high, color: careloopSuccess.withValues(alpha: 0.08))])
                    : null,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: lineColor,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      // Out-of-range points are also bigger with a ring, not just a different
                      // color — color-only signaling is invisible to colorblind users, and a
                      // health app's "this value needs attention" cue shouldn't depend on being
                      // able to distinguish red from green.
                      getDotPainter: (spot, percent, bar, index) {
                        final flag = rangeType == 'interpretive_rule' ? null : points[index]['in_range_flag'] as String?;
                        final outOfRange = flag == 'out_of_range';
                        return FlDotCirclePainter(
                          radius: outOfRange ? 5.5 : 3.5,
                          color: dotColor(flag),
                          strokeWidth: outOfRange ? 2 : 0,
                          strokeColor: careloopSurface,
                        );
                      },
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutCubic,
            ),
          ),
          if (rangeType == 'interpretive_rule')
            const Text('Interpretive index — raw value shown, no automated flag (Section 4.6).', style: TextStyle(color: careloopMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _QualitativeTimeline extends StatelessWidget {
  final Map<String, dynamic> param;
  const _QualitativeTimeline({required this.param});

  @override
  Widget build(BuildContext context) {
    final points = param['points'] as List<dynamic>;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(param['display_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in points) StatusPill('${p['test_date']}: ${p['raw_value']}')],
          ),
        ],
      ),
    );
  }
}
