import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../widgets/section_card.dart';

/// Health Timeline tab — every result, chronologically, with a small up/down/same/new indicator
/// against the previous reading of that same parameter. Deterministic (no model call): the delta
/// is computed server-side purely from date-ordered value comparisons.
class HealthTimelineTab extends StatefulWidget {
  final String memberId;
  const HealthTimelineTab({super.key, required this.memberId});
  @override
  State<HealthTimelineTab> createState() => _HealthTimelineTabState();
}

class _HealthTimelineTabState extends State<HealthTimelineTab> {
  List<dynamic>? _timeline;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final t = await api.getHealthTimeline(widget.memberId);
    if (mounted) setState(() => _timeline = t);
  }

  @override
  Widget build(BuildContext context) {
    if (_timeline == null) return const LoadingCenter();
    final entries = _timeline!.cast<Map<String, dynamic>>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          const SectionCaption('Health Timeline', icon: Icons.timeline_rounded),
          const Padding(
            padding: EdgeInsets.only(left: 24, bottom: 10),
            child: Text('Track your health data over time', style: TextStyle(color: careloopMuted, fontSize: careloopTypeCaption - 0.5)),
          ),
          if (entries.isEmpty)
            const InfoBanner('No results on file yet — your health timeline will build up as documents are uploaded and reviewed.', info: true)
          else
            for (final entry in entries)
              _TimelineDateGroup(date: entry['test_date'] as String? ?? '', parameters: (entry['parameters'] as List<dynamic>).cast<Map<String, dynamic>>()),
        ],
      ),
    );
  }
}

IconData _deltaIcon(String? delta) => switch (delta) {
      'up' => Icons.arrow_upward_rounded,
      'down' => Icons.arrow_downward_rounded,
      'same' => Icons.remove_rounded,
      _ => Icons.fiber_new_rounded,
    };

Color _deltaColor(String? delta) => switch (delta) {
      'up' => careloopDanger,
      'down' => careloopInfo,
      'same' => careloopMuted,
      _ => careloopSuccess,
    };

class _TimelineDateGroup extends StatelessWidget {
  final String date;
  final List<Map<String, dynamic>> parameters;
  const _TimelineDateGroup({required this.date, required this.parameters});

  @override
  Widget build(BuildContext context) {
    // A timeline gutter (dot + connecting line, stretched to the group's full height via
    // IntrinsicHeight) sits to the left of each date group's content, in the same spot as the
    // calendar-symbol/date row and card — the vertical line between dots is what makes this read
    // as a timeline rather than a plain grouped list.
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: careloopPrimary, shape: BoxShape.circle)),
                  const SizedBox(height: 4),
                  Expanded(child: Center(child: Container(width: 2, color: careloopBorder))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.calendar_today_rounded, size: 13, color: careloopMuted),
                    const SizedBox(width: 7),
                    Text(date, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: careloopTextPrimary)),
                  ]),
                  const SizedBox(height: 9),
                  Container(
                    decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        for (var i = 0; i < parameters.length; i++) ...[
                          _TimelineParamRow(param: parameters[i]),
                          if (i < parameters.length - 1) const Divider(height: 1),
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
}

class _TimelineParamRow extends StatelessWidget {
  final Map<String, dynamic> param;
  const _TimelineParamRow({required this.param});

  @override
  Widget build(BuildContext context) {
    final delta = param['delta'] as String?;
    final flag = param['in_range_flag'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(children: [
        Icon(_deltaIcon(delta), size: 15, color: _deltaColor(delta)),
        const SizedBox(width: 10),
        Expanded(
          // maxLines + ellipsis on both — without them, a narrow available width (e.g. the left
          // nav expanded) forced "Cholesterol" to break mid-word instead of eliding cleanly.
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(param['display_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: careloopTypeBody - 1, fontWeight: FontWeight.w600, color: careloopTextPrimary)),
            Text(param['category'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: careloopTypeCaption - 0.5, fontWeight: FontWeight.w400, color: careloopMuted)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${param['value'] ?? '—'}', style: careloopDataInline()),
          if (flag == 'out_of_range' || flag == 'in_range') ...[
            const SizedBox(height: 3),
            LedgerFlag(flag == 'out_of_range' ? 'Out of range' : 'In range', outOfRange: flag == 'out_of_range'),
          ],
        ]),
      ]),
    );
  }
}
