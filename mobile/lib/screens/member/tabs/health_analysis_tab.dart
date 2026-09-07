import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth_provider.dart';
import '../../../theme.dart';
import '../../../utils/motion.dart';
import '../../../utils/range_format.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_card.dart';
import 'document_viewer_screen.dart';

/// Health Analysis — panel-grouped Latest-vs-Previous comparison, redesigned per the reference
/// mockup. Kept compact: the left nav can be expanded (128px), leaving ~280px for this content,
/// so this uses 3 columns (parameter+range folded together, latest, previous) rather than the
/// reference's separate 4th "Reference Range" column.
class HealthAnalysisTab extends StatefulWidget {
  final String memberId;
  const HealthAnalysisTab({super.key, required this.memberId});
  @override
  State<HealthAnalysisTab> createState() => _HealthAnalysisTabState();
}

class _HealthAnalysisTabState extends State<HealthAnalysisTab> {
  List<dynamic>? _categories;
  String? _selectedCategory;
  Map<String, dynamic>? _data;
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final api = context.read<AuthProvider>().api;
    final categories = await api.getHealthAnalysisCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _selectedCategory = categories.isNotEmpty ? categories.first as String : null;
    });
    if (_selectedCategory != null) _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loadingData = true);
    final api = context.read<AuthProvider>().api;
    final data = await api.getHealthAnalysis(widget.memberId, _selectedCategory!);
    if (mounted) setState(() { _data = data; _loadingData = false; });
  }

  void _selectCategory(String category) {
    if (category == _selectedCategory) return;
    setState(() => _selectedCategory = category);
    _loadData();
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('How this comparison works'),
        content: const Text(
          'For each panel, we compare the two most recent lab reports that share the most results in common — usually your latest report against your last comparable one. '
          '"Improved" or "Declined" is judged by whether a result moved into or out of its normal range, not just whether the number went up or down.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_categories == null) return const LoadingCenter();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, careloopFabClearance),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health Analysis', style: careloopSectionHeading().copyWith(fontSize: 16)),
                  const Text('Compare your lab reports', style: TextStyle(color: careloopMuted, fontSize: 10)),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _showInfo,
              child: Container(width: 26, height: 26, decoration: BoxDecoration(color: careloopSurface, shape: BoxShape.circle, border: careloopCardBorder), child: const Icon(Icons.info_outline_rounded, size: 13, color: careloopMuted)),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories!.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categories![i] as String;
                final selected = cat == _selectedCategory;
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _selectCategory(cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(color: selected ? careloopPrimary : careloopSurface, borderRadius: BorderRadius.circular(999), border: selected ? null : careloopCardBorder),
                    alignment: Alignment.center,
                    child: Text(cat, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? Colors.white : careloopTextPrimary)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingData || _data == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (_data!['document1'] == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: EmptyState(icon: Icons.compare_arrows_rounded, message: 'Nothing to compare yet — a second report sharing results with this one will unlock this view.'),
            )
          else
            _PopulatedView(data: _data!, memberId: widget.memberId),
        ],
      ),
    );
  }
}

class _PopulatedView extends StatelessWidget {
  final Map<String, dynamic> data;
  final String memberId;
  const _PopulatedView({required this.data, required this.memberId});

  @override
  Widget build(BuildContext context) {
    final doc1 = data['document1'] as Map<String, dynamic>;
    final doc2 = data['document2'] as Map<String, dynamic>;
    final groups = (data['groups'] as List).cast<Map<String, dynamic>>();
    final summary = data['summary'] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: _ReportChip(label: 'LATEST', date: doc2['test_date'], lab: doc2['source_lab_name'], color: careloopAccent, bg: careloopAccentLight)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('VS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: careloopMutedDim))),
          Expanded(child: _ReportChip(label: 'PREVIOUS', date: doc1['test_date'], lab: doc1['source_lab_name'], color: careloopMutedDim, bg: careloopSurfaceRaised)),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in groups) _GroupSection(subPanel: g['sub_panel'] as String?, rows: (g['rows'] as List).cast<Map<String, dynamic>>()),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: careloopSurface, borderRadius: BorderRadius.circular(careloopRadiusMd), border: careloopCardBorder, boxShadow: careloopCardShadow),
          child: Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: careloopLavender, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.show_chart_rounded, size: 14, color: careloopSuccess)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Overall Summary', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('${summary['total']} parameters compared', style: const TextStyle(fontSize: 8.5, color: careloopMuted)),
                ],
              ),
            ),
            Text('↑${summary['improved']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: careloopGreen)),
            const SizedBox(width: 6),
            Text('–${summary['no_change']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: careloopMutedDim)),
            const SizedBox(width: 6),
            Text('↓${summary['declined']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: careloopDanger)),
          ]),
        ),
        if (doc2['document_id'] != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(pushRoute(DocumentViewerScreen(documentId: doc2['document_id'] as String))),
            icon: const Icon(Icons.description_rounded, size: 15),
            label: const Text('View Full Report'),
          ),
        ],
      ],
    );
  }
}

class _ReportChip extends StatelessWidget {
  final String label;
  final String date;
  final String? lab;
  final Color color;
  final Color bg;
  const _ReportChip({required this.label, required this.date, required this.lab, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: careloopTextPrimary)),
          if (lab != null) Text(lab!, style: const TextStyle(fontSize: 8.5, color: careloopMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  final String? subPanel;
  final List<Map<String, dynamic>> rows;
  const _GroupSection({required this.subPanel, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subPanel != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 4, top: 4),
            decoration: BoxDecoration(color: careloopAccentLight, borderRadius: BorderRadius.circular(10)),
            child: Text(subPanel!.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: careloopAccent, letterSpacing: 0.4)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(children: const [
              Expanded(flex: 13, child: Text('PARAMETER', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: careloopMutedDim))),
              Expanded(flex: 10, child: Text('LATEST', textAlign: TextAlign.right, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: careloopMutedDim))),
              Expanded(flex: 10, child: Text('PREV.', textAlign: TextAlign.right, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: careloopMutedDim))),
            ]),
          ),
        ],
        for (final r in rows) _ParamRow(row: r),
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ParamRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final rangeText = formatReferenceRange(row['range_type'] as String?, row['resolved_reference_range'] as Map<String, dynamic>?);
    final newValue = row['new_value'];
    final priorValue = row['prior_value'];
    final inRange = row['in_range_flag'] == 'in_range';
    final flag = row['in_range_flag'] == null ? null : flagWord(row['in_range_flag'], row['range_type'] as String?, newValue is num ? newValue : null, row['resolved_reference_range'] as Map<String, dynamic>?);
    final pillLabel = flag == 'In range' ? 'Normal' : (flag ?? '');
    final pillColor = inRange ? careloopGreen : careloopDanger;
    final pillBg = inRange ? careloopGreenBg : careloopAbnormalBg;
    final trend = row['trend'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: careloopBorder, width: 1))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 13,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row['display_name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${row['unit'] ?? ''}${rangeText.isNotEmpty ? ' · $rangeText' : ''}', style: const TextStyle(fontSize: 8, color: careloopMutedDim), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Expanded(
          flex: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${newValue ?? '—'}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: inRange ? careloopTextPrimary : careloopDanger)),
                if (trend != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    trend == 'up' ? Icons.arrow_upward_rounded : trend == 'down' ? Icons.arrow_downward_rounded : Icons.remove_rounded,
                    size: 10,
                    color: trend == 'up' ? careloopGreen : trend == 'down' ? careloopDanger : careloopMutedDim,
                  ),
                ],
              ]),
              if (pillLabel.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                  child: Text(pillLabel, style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: pillColor)),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 10,
          child: Text('${priorValue ?? '—'}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, color: careloopMuted)),
        ),
      ]),
    );
  }
}
